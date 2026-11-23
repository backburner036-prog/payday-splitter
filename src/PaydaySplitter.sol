// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractPayer} from "@reactive/src/base/AbstractPayer.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

/**
 * @title PaydaySplitter
 * @notice Origin + destination contract for the Reactive Omni Buildathon
 *         ("Set It and Forget It" track). Lives on Unichain Sepolia.
 *
 * Flow (the full loop):
 *   1. A user registers a split plan (savings / bills / fun) with `setPlan`.
 *   2. On payday the user calls `payday()` with ETH. The ETH sits in escrow
 *      and `PaydayReceived` is emitted.
 *   3. `PaydayReactive` on Reactive Lasna sees the event and requests a
 *      cross-chain callback to this contract.
 *   4. The Reactive callback proxy calls `splitPayday()`, which distributes
 *      the escrowed ETH to the three beneficiaries — no bot, no keeper.
 *
 * The contract pays its own callback gas (destination side) out of its ETH
 * balance via `AbstractPayer` (service provider = Unichain Sepolia callback
 * proxy). Top it up with plain ETH transfers.
 */
contract PaydaySplitter is AbstractPayer {
    /// @notice Unichain Sepolia callback proxy (Reactive Network).
    IPayable public immutable CALLBACK_PROXY;

    /// @notice Minimum payday deposit (dust filter, also enforced on Lasna).
    uint256 public constant MIN_PAYDAY = 0.001 ether;

    /// @notice Split shares are in basis points; must sum to 10_000.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public owner;

    /// @notice Reactive contract authorised to trigger splits (set after deploy).
    address public authorizedReactive;

    struct Plan {
        address savings;
        address bills;
        address fun;
        uint16 savingsBps;
        uint16 billsBps;
        uint16 funBps;
        bool exists;
    }

    mapping(address => Plan) public plans;
    /// @notice ETH currently escrowed per user, awaiting the reactive split.
    mapping(address => uint256) public pending;

    uint256 public totalPaydays;
    uint256 public totalSplit;
    uint256 public totalSplits;

    event PlanSet(
        address indexed user,
        address indexed savings,
        address indexed bills,
        address fun,
        uint16 savingsBps,
        uint16 billsBps,
        uint16 funBps
    );
    event PaydayReceived(address indexed user, uint256 amount, uint256 timestamp);
    event PaydaySplit(
        address indexed user,
        uint256 amount,
        uint256 savingsAmount,
        uint256 billsAmount,
        uint256 funAmount,
        uint256 timestamp
    );
    event ReactiveAuthorized(address indexed reactive);

    error NotOwner(address sender);
    error NotCallbackProxy(address sender);
    error NotAuthorizedReactive(address sender, address expected);
    error BadPlan();
    error ZeroAddress();
    error DustAmount(uint256 amount);
    error InsufficientPending(uint256 requested, uint256 available);
    error NoPlan(address user);
    error Reentrant();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert Reentrant();
        _locked = true;
        _;
        _locked = false;
    }

    bool private _locked;

    constructor(address payable callbackProxy_) AbstractPayer(IPayable(callbackProxy_)) {
        if (callbackProxy_ == address(0)) revert ZeroAddress();
        CALLBACK_PROXY = IPayable(callbackProxy_);
        owner = msg.sender;
    }

    /// @notice Point this splitter at the deployed reactive contract (owner only).
    function setReactive(address reactive_) external onlyOwner {
        if (reactive_ == address(0)) revert ZeroAddress();
        authorizedReactive = reactive_;
        emit ReactiveAuthorized(reactive_);
    }

    /// @notice Register (or replace) your split plan. Shares must sum to 100%.
    function setPlan(
        address savings_,
        address bills_,
        address fun_,
        uint16 savingsBps_,
        uint16 billsBps_,
        uint16 funBps_
    ) external {
        if (savings_ == address(0) || bills_ == address(0) || fun_ == address(0)) {
            revert ZeroAddress();
        }
        if (uint256(savingsBps_) + uint256(billsBps_) + uint256(funBps_) != BPS_DENOMINATOR) {
            revert BadPlan();
        }
        plans[msg.sender] = Plan({
            savings: savings_,
            bills: bills_,
            fun: fun_,
            savingsBps: savingsBps_,
            billsBps: billsBps_,
            funBps: funBps_,
            exists: true
        });
        emit PlanSet(msg.sender, savings_, bills_, fun_, savingsBps_, billsBps_, funBps_);
    }

    /// @notice Payday! Deposit ETH; the reactive contract splits it for you.
    function payday() external payable {
        if (msg.value < MIN_PAYDAY) revert DustAmount(msg.value);
        if (!plans[msg.sender].exists) revert NoPlan(msg.sender);
        if (!_seenUser[msg.sender]) {
            _seenUser[msg.sender] = true;
            _paydayUsers.push(msg.sender);
        }
        pending[msg.sender] += msg.value;
        totalPaydays += 1;
        emit PaydayReceived(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @notice Called by the Reactive callback proxy on behalf of the
     *         authorised reactive contract. Splits one escrowed payday.
     * @dev First payload argument is the reactive contract address, injected
     *      by Reactive Network (the caller passes address(0) as placeholder).
     */
    function splitPayday(address rvmId_, address user_, uint256 amount_) external nonReentrant {
        if (msg.sender != address(CALLBACK_PROXY)) revert NotCallbackProxy(msg.sender);
        if (rvmId_ != authorizedReactive) revert NotAuthorizedReactive(rvmId_, authorizedReactive);
        if (amount_ > pending[user_]) {
            revert InsufficientPending(amount_, pending[user_]);
        }
        Plan memory plan = plans[user_];
        if (!plan.exists) revert NoPlan(user_);

        pending[user_] -= amount_;
        totalSplit += amount_;
        totalSplits += 1;

        uint256 savingsAmount = (amount_ * plan.savingsBps) / BPS_DENOMINATOR;
        uint256 billsAmount = (amount_ * plan.billsBps) / BPS_DENOMINATOR;
        // Dust remainder (integer division) goes to fun (last bucket).
        uint256 funAmount = amount_ - savingsAmount - billsAmount;

        _send(plan.savings, savingsAmount);
        _send(plan.bills, billsAmount);
        _send(plan.fun, funAmount);

        emit PaydaySplit(user_, amount_, savingsAmount, billsAmount, funAmount, block.timestamp);
    }

    /// @notice Owner can top up / withdraw surplus ETH (never users' escrow).
    /// @dev Withdrawable = balance minus total escrowed pending.
    function withdrawSurplus(uint256 amount_) external onlyOwner nonReentrant {
        uint256 surplus = address(this).balance - _totalPending();
        require(amount_ <= surplus, "exceeds surplus");
        _send(owner, amount_);
    }

    function _send(address to_, uint256 amount_) internal {
        if (amount_ == 0) return;
        (bool ok,) = payable(to_).call{value: amount_}("");
        require(ok, "transfer failed");
    }

    // --- bookkeeping for the surplus view (bounded: demo-scale user set) ---
    address[] private _paydayUsers;
    mapping(address => bool) private _seenUser;

    function _totalPending() internal view returns (uint256 sum) {
        for (uint256 i = 0; i < _paydayUsers.length; i++) {
            sum += pending[_paydayUsers[i]];
        }
    }

    /// @notice Number of distinct users that ever had a payday (demo helper).
    function paydayUserCount() external view returns (uint256) {
        return _paydayUsers.length;
    }
}
