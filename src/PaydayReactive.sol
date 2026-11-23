// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/**
 * @title PaydayReactive
 * @notice Reactive contract for the Reactive Omni Buildathon
 *         ("Set It and Forget It" track). Lives on Reactive Lasna.
 *
 * Watches `PaydaySplitter.payday()` events on Unichain Sepolia and, for every
 * payday at or above the dust threshold, requests a cross-chain callback that
 * makes the splitter distribute the escrowed ETH to the user's
 * savings / bills / fun beneficiaries. No bot, no keeper, no polling:
 * the split is triggered purely by the on-chain event.
 *
 * Funding: keep this contract topped up with lREACT — reactive transactions
 * and callback requests are billed from its balance by the system contract.
 */
contract PaydayReactive is AbstractReactive {
    /// @notice keccak256("PaydayReceived(address,uint256,uint256)")
    uint256 public immutable PAYDAY_TOPIC0;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable ORIGIN_CONTRACT;
    uint256 public immutable DEST_CHAIN_ID;
    address public immutable DEST_CONTRACT;
    uint64 public immutable CALLBACK_GAS_LIMIT;
    uint256 public immutable MIN_PAYDAY;

    uint256 public splitsRequested;
    address public lastUser;
    uint256 public lastAmount;
    uint256 public lastOriginTxHash;

    event SplitRequested(address indexed user, uint256 amount, uint256 originTxHash);
    event SplitSkippedDust(address indexed user, uint256 amount);

    /// @param originChainId_   Chain the splitter lives on (Unichain Sepolia = 1301).
    /// @param originContract_  PaydaySplitter address on the origin chain.
    /// @param paydayTopic0_    Topic0 of PaydayReceived.
    /// @param destChainId_     Callback destination chain (1301).
    /// @param destContract_    PaydaySplitter address (callback recipient).
    /// @param callbackGasLimit_ Gas for the destination split call (>= 100_000).
    /// @param minPayday_       Paydays below this are ignored (dust filter).
    constructor(
        uint256 originChainId_,
        address originContract_,
        uint256 paydayTopic0_,
        uint256 destChainId_,
        address destContract_,
        uint64 callbackGasLimit_,
        uint256 minPayday_
    ) payable {
        ORIGIN_CHAIN_ID = originChainId_;
        ORIGIN_CONTRACT = originContract_;
        PAYDAY_TOPIC0 = paydayTopic0_;
        DEST_CHAIN_ID = destChainId_;
        DEST_CONTRACT = destContract_;
        CALLBACK_GAS_LIMIT = callbackGasLimit_;
        MIN_PAYDAY = minPayday_;

        SYSTEM.subscribe(
            originChainId_, originContract_, paydayTopic0_, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Route: only our payday event, from the origin chain, LOG2 shape
        // (topic0 = signature, topic1 = indexed user; amount+timestamp in data).
        if (log_.topic0 != PAYDAY_TOPIC0) return;
        if (log_.chainId != ORIGIN_CHAIN_ID) return;
        if (log_.contractAddress != ORIGIN_CONTRACT) return;
        if (log_.opCode != 2 || log_.data.length < 64) return;

        address user = address(uint160(log_.topic1));
        (uint256 amount,) = abi.decode(log_.data, (uint256, uint256));

        if (amount < MIN_PAYDAY) {
            emit SplitSkippedDust(user, amount);
            return;
        }

        splitsRequested += 1;
        lastUser = user;
        lastAmount = amount;
        lastOriginTxHash = log_.txHash;
        emit SplitRequested(user, amount, log_.txHash);

        // First payload arg is a placeholder: Reactive overwrites it with
        // this contract's address so the splitter can authenticate the call.
        bytes memory payload = abi.encodeWithSignature("splitPayday(address,address,uint256)", address(0), user, amount);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID, recipient: DEST_CONTRACT, gasLimit: CALLBACK_GAS_LIMIT, payload: payload
            })
        );
    }
}
