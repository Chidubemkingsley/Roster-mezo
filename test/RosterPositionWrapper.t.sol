// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {RosterPositionWrapper} from "../src/RosterPositionWrapper.sol";

contract RosterPositionWrapperTest is TestBase {
    RosterPositionWrapper internal wrapper;
    uint256 internal constant WRAP = 1e18;

    function setUp() public override {
        super.setUp();
        wrapper = new RosterPositionWrapper(series, "Wrapped Roster Put", "wRBTC-PUT");
        _deposit(100 * WAD);
        _buy(alice, 10);

        vm.prank(alice);
        series.approve(address(wrapper), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(wrapper), type(uint256).max);
    }

    function test_deposit_and_withdraw_round_trip() public {
        vm.prank(alice);
        wrapper.deposit(10);

        _assertEq(wrapper.balanceOf(alice), 10 * WRAP, "wrapper balance");
        _assertEq(wrapper.totalSupply(), 10 * WRAP, "wrapper supply");
        _assertEq(series.balanceOf(address(wrapper)), 10, "underlying lots");
        _assertEq(wrapper.underlyingLots(), 10, "underlying getter");

        vm.prank(alice);
        wrapper.withdraw(4 * WRAP);

        _assertEq(wrapper.balanceOf(alice), 6 * WRAP, "wrapper balance after withdraw");
        _assertEq(wrapper.totalSupply(), 6 * WRAP, "wrapper supply after withdraw");
        _assertEq(series.balanceOf(address(wrapper)), 6, "underlying lots after withdraw");
        _assertEq(series.balanceOf(alice), 4, "series balance returned");
    }

    function test_transfer_and_allowance() public {
        vm.prank(alice);
        wrapper.deposit(10);

        vm.prank(alice);
        wrapper.transfer(bob, 3 * WRAP);
        _assertEq(wrapper.balanceOf(alice), 7 * WRAP, "alice after transfer");
        _assertEq(wrapper.balanceOf(bob), 3 * WRAP, "bob after transfer");

        vm.prank(alice);
        wrapper.approve(spender, 2 * WRAP);
        vm.prank(spender);
        wrapper.transferFrom(alice, carol, 2 * WRAP);

        _assertEq(wrapper.balanceOf(alice), 5 * WRAP, "alice after transferFrom");
        _assertEq(wrapper.balanceOf(carol), 2 * WRAP, "carol after transferFrom");
        _assertEq(wrapper.allowance(alice, spender), 0, "allowance consumed");
    }

    function test_exercise_via_wrapper() public {
        vm.prank(alice);
        wrapper.deposit(10);

        uint256 aliceBtcBefore = btc.balanceOf(alice);
        uint256 aliceMUSDBefore = musd.balanceOf(alice);
        uint256 writerBtcBefore = btc.balanceOf(writer);

        vm.prank(alice);
        wrapper.exercise(4 * WRAP);

        _assertEq(btc.balanceOf(alice), aliceBtcBefore - 4 * series.LOT_SIZE_RAW(), "BTC debit");
        _assertEq(btc.balanceOf(writer), writerBtcBefore + 4 * series.LOT_SIZE_RAW(), "writer BTC");
        _assertEq(musd.balanceOf(alice), aliceMUSDBefore + 4 * series.strike_per_lot_raw(), "MUSD payout forwarded");
        _assertEq(wrapper.balanceOf(alice), 6 * WRAP, "wrapper balance after exercise");
        _assertEq(wrapper.totalSupply(), 6 * WRAP, "wrapper supply after exercise");
        _assertEq(series.balanceOf(address(wrapper)), 6, "underlying after exercise");
        _assertEq(series.active_lots(), 6, "series active lots");
        _checkLiveAccounting();
    }

    function test_deposit_requires_series_approval() public {
        vm.prank(alice);
        series.approve(address(wrapper), 0);

        vm.expectRevert(RosterBtcPutSeries.InsufficientAllowance.selector);
        vm.prank(alice);
        wrapper.deposit(1);
    }

    function test_exercise_requires_btc_approval() public {
        vm.prank(alice);
        wrapper.deposit(1);
        vm.prank(alice);
        btc.approve(address(wrapper), 0);

        vm.expectRevert();
        vm.prank(alice);
        wrapper.exercise(WRAP);
    }

    function test_non_multiple_and_zero_amounts_revert() public {
        vm.expectRevert(RosterPositionWrapper.InvalidQuantity.selector);
        vm.prank(alice);
        wrapper.deposit(0);

        vm.expectRevert(RosterPositionWrapper.InvalidQuantity.selector);
        vm.prank(alice);
        wrapper.withdraw(1);

        vm.expectRevert(RosterPositionWrapper.InvalidQuantity.selector);
        vm.prank(alice);
        wrapper.exercise(1);
    }

    function test_expiry_blocks_settlement_but_not_wrapper_transfers() public {
        vm.prank(alice);
        wrapper.deposit(2);
        vm.warp(expiryTime);

        vm.expectRevert(RosterPositionWrapper.NotLive.selector);
        vm.prank(alice);
        wrapper.deposit(1);

        vm.expectRevert(RosterPositionWrapper.NotLive.selector);
        vm.prank(alice);
        wrapper.withdraw(WRAP);

        vm.expectRevert(RosterPositionWrapper.NotLive.selector);
        vm.prank(alice);
        wrapper.exercise(WRAP);

        // Wrapper transfers remain available so a pool or other holder can unwind.
        vm.prank(alice);
        wrapper.transfer(bob, WRAP);
        _assertEq(wrapper.balanceOf(bob), WRAP, "post-expiry wrapper transfer");
    }

    function test_underlying_and_supply_stay_in_sync() public {
        vm.prank(alice);
        wrapper.deposit(10);
        vm.prank(alice);
        wrapper.exercise(3 * WRAP);
        vm.prank(alice);
        wrapper.withdraw(2 * WRAP);

        _assertEq(wrapper.underlyingLots() * WRAP, wrapper.totalSupply(), "1:1 backing");
        _assertEq(series.balanceOf(address(wrapper)), 5, "remaining underlying");
    }

    function test_withdraw_to_writer_reverts() public {
        vm.prank(alice);
        wrapper.deposit(1);
        vm.prank(alice);
        wrapper.transfer(writer, WRAP);

        vm.expectRevert(RosterBtcPutSeries.InvalidRecipient.selector);
        vm.prank(writer);
        wrapper.withdraw(WRAP);
    }
}
