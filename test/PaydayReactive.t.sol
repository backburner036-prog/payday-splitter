// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {PaydayReactive} from "../src/PaydayReactive.sol";

/// @notice Minimal stand-in for the Reactive system contract (test-only).
/// @dev State is deliberately NOT stored here: tests etch this code onto the
///      SYSTEM address, so storage lives at SYSTEM, not at this contract.
///      Behaviour is asserted via events + `vm.load(SYSTEM, slot)`.
contract MockSystem {
    event Subscribed(uint256 chainId, address contract_, uint256 topic0);
    event CallbackRequested(uint256 chainId, address recipient, uint64 gasLimit, bytes payload);

    uint256 public subscribeCount;

    function subscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256, uint256, uint256) external {
        subscribeCount += 1;
        emit Subscribed(chainId_, contract_, topic0_);
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        emit CallbackRequested(config_.chainId, config_.recipient, config_.gasLimit, config_.payload);
    }
}

contract PaydayReactiveTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 constant ORIGIN_CHAIN = 1301; // Unichain Sepolia
    address constant SPLITTER = address(0x5EED);
    uint256 constant TOPIC0 = 0x026ea514fc5e4e223bbdaf9d66e602619ec85302d4740f05480dc01bb7eec65c;
    address constant USER = address(0xA11CE);

    MockSystem mockSystem;
    PaydayReactive reactive;

    function setUp() public {
        mockSystem = new MockSystem();
        vm.etch(SYSTEM, address(mockSystem).code);
        reactive = new PaydayReactive(ORIGIN_CHAIN, SPLITTER, TOPIC0, ORIGIN_CHAIN, SPLITTER, 500_000, 0.001 ether);
    }

    function _log(uint256 topic0_, uint256 amount_) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: ORIGIN_CHAIN,
            contractAddress: SPLITTER,
            topic0: topic0_,
            topic1: uint256(uint160(USER)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount_, block.timestamp),
            blockNumber: block.number,
            opCode: 2,
            blockHash: 0,
            txHash: 0xABCDEF,
            logIndex: 0
        });
    }

    function testConstructorSubscribes() public view {
        // subscribeCount lives in SYSTEM storage slot 0 (etched code).
        uint256 subs = uint256(vm.load(SYSTEM, bytes32(uint256(0))));
        assertEq(subs, 1);
    }

    function testReactRequestsSplitOnPayday() public {
        bytes memory expectedPayload =
            abi.encodeWithSignature("splitPayday(address,address,uint256)", address(0), USER, 1 ether);
        vm.expectEmit(false, false, false, true, SYSTEM);
        emit MockSystem.CallbackRequested(ORIGIN_CHAIN, SPLITTER, 500_000, expectedPayload);

        vm.prank(SYSTEM);
        reactive.react(_log(TOPIC0, 1 ether));
        assertEq(reactive.splitsRequested(), 1);
        assertEq(reactive.lastUser(), USER);
        assertEq(reactive.lastAmount(), 1 ether);
        assertEq(reactive.lastOriginTxHash(), 0xABCDEF);
    }

    function testReactIgnoresWrongTopic() public {
        vm.prank(SYSTEM);
        reactive.react(_log(0x1234, 1 ether));
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactIgnoresWrongChain() public {
        IReactive.LogRecord memory log = _log(TOPIC0, 1 ether);
        log.chainId = 84532; // Base Sepolia, not our origin
        vm.prank(SYSTEM);
        reactive.react(log);
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactSkipsDust() public {
        vm.prank(SYSTEM);
        reactive.react(_log(TOPIC0, 0.0005 ether));
        assertEq(reactive.splitsRequested(), 0);
    }

    function testReactRejectsNonSystem() public {
        vm.prank(USER);
        vm.expectRevert();
        reactive.react(_log(TOPIC0, 1 ether));
    }

    function testReactIgnoresShortData() public {
        IReactive.LogRecord memory log = _log(TOPIC0, 1 ether);
        log.data = hex"00";
        vm.prank(SYSTEM);
        reactive.react(log);
        assertEq(reactive.splitsRequested(), 0);
    }
}
