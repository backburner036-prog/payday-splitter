// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {PaydaySplitter} from "../src/PaydaySplitter.sol";

contract PaydaySplitterTest is Test {
    address constant PROXY = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4; // Unichain Sepolia callback proxy
    address constant REACTIVE = address(0xBEEF);
    address constant USER = address(0xA11CE);
    address constant SAVINGS = address(0x5A1);
    address constant BILLS = address(0xB111);
    address constant FUN = address(0xF09);

    PaydaySplitter splitter;

    function setUp() public {
        splitter = new PaydaySplitter(payable(PROXY));
        splitter.setReactive(REACTIVE);
        vm.deal(USER, 10 ether);
        vm.deal(address(splitter), 1 ether); // callback-gas float
        vm.prank(USER);
        splitter.setPlan(SAVINGS, BILLS, FUN, 5000, 3000, 2000);
    }

    function testSetPlanRejectsBadShares() public {
        vm.prank(USER);
        vm.expectRevert(PaydaySplitter.BadPlan.selector);
        splitter.setPlan(SAVINGS, BILLS, FUN, 5000, 3000, 1999);
    }

    function testSetPlanRejectsZeroAddress() public {
        vm.prank(USER);
        vm.expectRevert(PaydaySplitter.ZeroAddress.selector);
        splitter.setPlan(address(0), BILLS, FUN, 5000, 3000, 2000);
    }

    function testPaydayRequiresPlan() public {
        address stranger = address(0x999);
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PaydaySplitter.NoPlan.selector, stranger));
        splitter.payday{value: 0.01 ether}();
    }

    function testPaydayRejectsDust() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(PaydaySplitter.DustAmount.selector, 0.0005 ether));
        splitter.payday{value: 0.0005 ether}();
    }

    function testPaydayAccruesPending() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();
        assertEq(splitter.pending(USER), 1 ether);
        assertEq(splitter.totalPaydays(), 1);
        assertEq(splitter.paydayUserCount(), 1);
    }

    function testSplitHappyPath() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();

        uint256 s0 = SAVINGS.balance;
        uint256 b0 = BILLS.balance;
        uint256 f0 = FUN.balance;

        vm.prank(PROXY);
        splitter.splitPayday(REACTIVE, USER, 1 ether);

        assertEq(SAVINGS.balance - s0, 0.5 ether);
        assertEq(BILLS.balance - b0, 0.3 ether);
        assertEq(FUN.balance - f0, 0.2 ether);
        assertEq(splitter.pending(USER), 0);
        assertEq(splitter.totalSplit(), 1 ether);
        assertEq(splitter.totalSplits(), 1);
    }

    function testSplitDustRemainderGoesToFun() public {
        // 0.001 ether + 1 wei at 50/30/20:
        // savings 500000000000000, bills 300000000000000, fun 200000000000001.
        uint256 amount = 1000000000000001;
        vm.prank(USER);
        splitter.payday{value: amount}();

        vm.prank(PROXY);
        splitter.splitPayday(REACTIVE, USER, amount);

        assertEq(SAVINGS.balance, 500000000000000);
        assertEq(BILLS.balance, 300000000000000);
        assertEq(FUN.balance, 200000000000001);
    }

    function testSplitRejectsNonProxy() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(PaydaySplitter.NotCallbackProxy.selector, USER));
        splitter.splitPayday(REACTIVE, USER, 1 ether);
    }

    function testSplitRejectsWrongReactive() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();
        vm.prank(PROXY);
        vm.expectRevert(
            abi.encodeWithSelector(PaydaySplitter.NotAuthorizedReactive.selector, address(0xDEAD), REACTIVE)
        );
        splitter.splitPayday(address(0xDEAD), USER, 1 ether);
    }

    function testSplitRejectsOverPending() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();
        vm.prank(PROXY);
        vm.expectRevert(abi.encodeWithSelector(PaydaySplitter.InsufficientPending.selector, 2 ether, 1 ether));
        splitter.splitPayday(REACTIVE, USER, 2 ether);
    }

    function testPartialSplitKeepsRemainderPending() public {
        vm.prank(USER);
        splitter.payday{value: 1 ether}();
        vm.prank(PROXY);
        splitter.splitPayday(REACTIVE, USER, 0.4 ether);
        assertEq(splitter.pending(USER), 0.6 ether);
        assertEq(SAVINGS.balance, 0.2 ether);
    }

    function testOnlyOwnerSetsReactive() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(PaydaySplitter.NotOwner.selector, USER));
        splitter.setReactive(address(0x1234));
    }
}
