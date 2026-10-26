// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {CallbackERC20, FeeOnTransferERC20} from "../src/TestERC20Helpers.sol";

contract RosterBtcPutSeriesTest is TestBase {
    function test_deposit_writer_only() public {
        vm.expectRevert(RosterBtcPutSeries.OnlyWriter.selector);
        vm.prank(alice);
        series.deposit(1 * WAD);
    }

    function test_deposit_updates_state() public {
        _deposit(10 * WAD);
        _assertEq(series.total_deposited_raw(), 10 * WAD, "total deposited");
        _assertEq(series.collateral_balance_raw(), 10 * WAD, "collateral");
        _assertEq(series.excess_raw(), 10 * WAD, "excess");
        _assertEq(series.reserved_raw(), 0, "reserve");
        _checkLiveAccounting();
    }

    function test_purchase_any_nonwriter() public {
        _deposit(10 * WAD);
        _buy(alice, 10);
        _assertEq(series.balanceOf(alice), 10, "buyer minted lots");
        _assertEq(series.balanceOf(writer), 0, "writer got no tokens");
        _assertEq(series.active_lots(), 10, "active lots");
        _assertEq(series.reserved_raw(), 10 * STRIKE_PER_LOT, "reserve");
        _assertEq(series.premium_balance_raw(), 10 * PREMIUM_PER_LOT, "premium credited");
        _checkLiveAccounting();
    }

    function test_purchase_writer_reverts() public {
        _deposit(1 * WAD);
        vm.expectRevert(RosterBtcPutSeries.WriterCannotPurchase.selector);
        vm.prank(writer);
        series.purchase(1);
    }

    function test_purchase_capacity() public {
        _deposit(2 * STRIKE_PER_LOT);
        vm.expectRevert(RosterBtcPutSeries.InsufficientExcess.selector);
        vm.prank(alice);
        series.purchase(3);
        _assertEq(series.totalSupply(), 0, "no mint on failed purchase");
        _assertEq(series.excess_raw(), 2 * STRIKE_PER_LOT, "excess unchanged");
    }

    function test_constructor_zero_premium_reverts() public {
        vm.expectRevert(RosterBtcPutSeries.InvalidPremium.selector);
        new RosterBtcPutSeries(writer, address(musd), address(btc), K_RAW, 0, expiryTime, "Zero Premium", "ZERO");
    }

    function test_zero_quantities_revert() public {
        vm.expectRevert(RosterBtcPutSeries.InvalidQuantity.selector);
        vm.prank(writer);
        series.deposit(0);

        vm.expectRevert(RosterBtcPutSeries.InvalidQuantity.selector);
        vm.prank(alice);
        series.purchase(0);

        vm.expectRevert(RosterBtcPutSeries.InvalidQuantity.selector);
        vm.prank(alice);
        series.exercise(0);
    }

    function test_transfer_to_writer_blocked() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.expectRevert(RosterBtcPutSeries.InvalidRecipient.selector);
        vm.prank(alice);
        series.transfer(writer, 1);
        _assertEq(series.balanceOf(alice), 2, "balance unchanged");
    }

    function test_transferFrom_to_writer_blocked() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.prank(alice);
        series.approve(spender, 2);
        vm.expectRevert(RosterBtcPutSeries.InvalidRecipient.selector);
        vm.prank(spender);
        series.transferFrom(alice, writer, 1);
        _assertEq(series.balanceOf(alice), 2, "balance unchanged");
        _assertEq(series.allowance(alice, spender), 2, "allowance unchanged on revert");
    }

    function test_exercise_self_only() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.expectRevert(RosterBtcPutSeries.InsufficientPositionTokens.selector);
        vm.prank(bob);
        series.exercise(1);
    }

    function test_exercise_writer_reverts() public {
        _deposit(STRIKE_PER_LOT);
        vm.expectRevert(RosterBtcPutSeries.WriterCannotExercise.selector);
        vm.prank(writer);
        series.exercise(1);
    }

    function test_exercise_exact_payout_no_rounding() public {
        _deposit(5 * STRIKE_PER_LOT);
        _buy(alice, 5);
        uint256 btcBefore = btc.balanceOf(alice);
        uint256 musdBefore = musd.balanceOf(alice);
        vm.prank(alice);
        series.exercise(3);
        _assertEq(btcBefore - btc.balanceOf(alice), 3 * series.LOT_SIZE_RAW(), "exact BTC debit");
        _assertEq(musd.balanceOf(alice) - musdBefore, 3 * STRIKE_PER_LOT, "exact MUSD payout");
        _assertEq(series.total_payouts_raw(), 3 * STRIKE_PER_LOT, "exact audit payout");
        _checkLiveAccounting();
    }

    function test_exercise_partial() public {
        _deposit(10 * WAD);
        _buy(alice, 10);
        uint256 reserveBefore = series.reserved_raw();
        uint256 excessBefore = series.excess_raw();
        vm.prank(alice);
        series.exercise(3);
        _assertEq(series.balanceOf(alice), 7, "remaining tokens");
        _assertEq(series.active_lots(), 7, "remaining active lots");
        _assertEq(series.reserved_raw(), reserveBefore - 3 * STRIKE_PER_LOT, "reserve reduced");
        _assertEq(series.excess_raw(), excessBefore, "excess unchanged");
        _checkLiveAccounting();
    }

    function test_exercise_after_expiry_reverts() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.warp(expiryTime);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.exercise(1);
    }

    function test_expire_permissionless_idempotent() public {
        _deposit(3 * STRIKE_PER_LOT);
        _buy(alice, 3);
        vm.expectRevert(RosterBtcPutSeries.NotMatured.selector);
        vm.prank(bob);
        series.expire();
        vm.warp(expiryTime);
        vm.prank(bob);
        series.expire();
        vm.prank(carol);
        series.expire();
        _assertTrue(series.expired(), "expired flag");
        _assertEq(series.collateral_balance_raw(), 0, "collateral cleared");
    }

    function test_expire_releases_all_collateral() public {
        _deposit(10 * WAD);
        _buy(alice, 10);
        vm.prank(alice);
        series.exercise(2);
        uint256 collateralBeforeExpiry = series.collateral_balance_raw();
        uint256 writerBefore = musd.balanceOf(writer);
        uint256 tokenSupplyBefore = series.totalSupply();
        uint256 alicePositionsBefore = series.balanceOf(alice);
        vm.warp(expiryTime);
        series.expire();
        _assertEq(musd.balanceOf(writer) - writerBefore, collateralBeforeExpiry, "all residual collateral returned");
        _assertEq(series.expiry_release_raw(), collateralBeforeExpiry, "release recorded");
        _assertEq(series.collateral_balance_raw(), 0, "collateral zero");
        _assertEq(series.reserved_raw(), 0, "reserve zero");
        _assertEq(series.excess_raw(), 0, "excess zero");
        _assertEq(series.active_lots(), 0, "live liability zero");
        _assertEq(series.totalSupply(), tokenSupplyBefore, "unburned supply remains");
        _assertEq(series.balanceOf(alice), alicePositionsBefore, "expired positions remain in wallet");
        _checkAudit();
        _checkSolvency();
    }

    function test_withdraw_premium_writer_only() public {
        _deposit(5 * WAD);
        _buy(alice, 5);
        uint256 premium = series.premium_balance_raw();
        uint256 collateralBefore = series.collateral_balance_raw();
        vm.expectRevert(RosterBtcPutSeries.OnlyWriter.selector);
        vm.prank(alice);
        series.withdrawPremium();
        uint256 writerBefore = musd.balanceOf(writer);
        vm.prank(writer);
        series.withdrawPremium();
        _assertEq(musd.balanceOf(writer) - writerBefore, premium, "premium received");
        _assertEq(series.premium_balance_raw(), 0, "premium liability cleared");
        _assertEq(series.collateral_balance_raw(), collateralBefore, "collateral unaffected");
        _checkSolvency();
    }

    function test_invariant_pre_and_post_expiry() public {
        _deposit(100 * WAD);
        _buy(alice, 10);
        vm.prank(alice);
        series.transfer(bob, 3);
        vm.prank(bob);
        series.exercise(1);
        _checkLiveAccounting();
        _assertEq(
            series.balanceOf(alice) + series.balanceOf(bob) + series.balanceOf(carol),
            series.totalSupply(),
            "tracked sum live"
        );
        vm.warp(expiryTime);
        _checkLiveAccounting(); // maturity/limbo: the collateral is still held until expire()
        series.expire();
        _assertEq(series.collateral_balance_raw(), 0, "post-expiry collateral");
        _assertEq(series.reserved_raw(), 0, "post-expiry reserve");
        _assertEq(series.excess_raw(), 0, "post-expiry excess");
        _assertEq(series.active_lots(), 0, "post-expiry active lots");
        _assertEq(
            series.balanceOf(alice) + series.balanceOf(bob) + series.balanceOf(carol),
            series.totalSupply(),
            "tracked sum finalized"
        );
        _checkAudit();
        _checkSolvency();
    }

    function test_solvency_after_every_action() public {
        _deposit(10 * WAD);
        _checkSolvency();
        _buy(alice, 10);
        _checkSolvency();
        vm.prank(alice);
        series.exercise(2);
        _checkSolvency();
        vm.prank(writer);
        series.withdrawPremium();
        _checkSolvency();
        vm.warp(expiryTime);
        series.expire();
        _checkSolvency();
    }

    function test_erc20_interface_and_totalSupply_pre_post_expiry() public {
        _deposit(10 * WAD);
        _buy(alice, 5);
        _assertEq(series.decimals(), 0, "zero decimals");
        _assertEq(series.totalSupply(), 5, "supply after mint");
        vm.prank(alice);
        series.transfer(bob, 2);
        _assertEq(series.totalSupply(), 5, "transfer keeps supply");
        _assertEq(series.balanceOf(alice), 3, "alice balance");
        _assertEq(series.balanceOf(bob), 2, "bob balance");
        vm.prank(bob);
        series.exercise(1);
        _assertEq(series.totalSupply(), 4, "burn reduces supply");
        _assertEq(series.active_lots(), 4, "active liability");
        uint256 supply = series.totalSupply();
        uint256 aliceBalance = series.balanceOf(alice);
        uint256 bobBalance = series.balanceOf(bob);
        vm.warp(expiryTime);
        series.expire();
        _assertEq(series.totalSupply(), supply, "supply fixed after expiry");
        _assertEq(series.balanceOf(alice), aliceBalance, "alice positions frozen");
        _assertEq(series.balanceOf(bob), bobBalance, "bob positions frozen");
        _assertEq(series.name(), "Roster Mezo BTC Put Series", "name");
        _assertEq(series.symbol(), "RBTC-PUT", "symbol");
    }

    function test_reentrancy_with_adversarial_token() public {
        (RosterBtcPutSeries s, MockERC20 m, CallbackERC20 btc) = _newCallbackSeries();
        vm.prank(writer);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(s), type(uint256).max);
        btc.mint(alice, 10 * WAD);
        vm.prank(writer);
        s.deposit(5 * WAD);
        vm.prank(alice);
        s.purchase(2);
        bytes memory payload = abi.encodeWithSelector(s.purchase.selector, 1);
        btc.configureCallback(address(s), address(s), payload, false);
        vm.prank(alice);
        s.exercise(1);
        _assertTrue(!btc.lastCallbackSucceeded(), "reentrant purchase rejected");
        _assertEq(
            btc.lastCallbackRevertSelector(), bytes4(keccak256("ReentrancyGuardReentrantCall()")), "guard selector"
        );
        _assertEq(s.active_lots(), 1, "only outer exercise applied");
        _assertEq(s.totalSupply(), 1, "supply matches outer exercise");
    }

    function test_constructor_invalid_params() public {
        vm.expectRevert(RosterBtcPutSeries.ZeroAddress.selector);
        new RosterBtcPutSeries(address(0), address(musd), address(btc), K_RAW, PREMIUM_PER_LOT, expiryTime, "X", "X");
        vm.expectRevert(RosterBtcPutSeries.IdenticalTokenAddresses.selector);
        new RosterBtcPutSeries(writer, address(musd), address(musd), K_RAW, PREMIUM_PER_LOT, expiryTime, "X", "X");
        vm.expectRevert(RosterBtcPutSeries.InvalidExpiry.selector);
        new RosterBtcPutSeries(writer, address(musd), address(btc), K_RAW, PREMIUM_PER_LOT, block.timestamp, "X", "X");
        vm.expectRevert(RosterBtcPutSeries.InvalidStrike.selector);
        new RosterBtcPutSeries(writer, address(musd), address(btc), 123, PREMIUM_PER_LOT, expiryTime, "X", "X");
        MockERC20 badDecimals = new MockERC20("Bad", "BAD", 6);
        vm.expectRevert(
            abi.encodeWithSelector(RosterBtcPutSeries.InvalidTokenDecimals.selector, address(badDecimals), 6)
        );
        new RosterBtcPutSeries(writer, address(badDecimals), address(btc), K_RAW, PREMIUM_PER_LOT, expiryTime, "X", "X");
    }

    function test_exercise_insufficient_btc_reverts() public {
        address noBtc = address(0xF00D);
        musd.mint(noBtc, 100 * WAD);
        vm.prank(noBtc);
        musd.approve(address(series), type(uint256).max);
        _deposit(STRIKE_PER_LOT);
        vm.prank(noBtc);
        series.purchase(1);
        vm.expectRevert(RosterBtcPutSeries.InsufficientBtcBalance.selector);
        vm.prank(noBtc);
        series.exercise(1);
        _checkLiveAccounting();
    }

    function test_exercise_insufficient_allowance_reverts() public {
        _deposit(STRIKE_PER_LOT);
        _buy(alice, 1);
        vm.prank(alice);
        btc.approve(address(series), 0);
        vm.expectRevert(RosterBtcPutSeries.InsufficientBtcAllowance.selector);
        vm.prank(alice);
        series.exercise(1);
        _assertEq(series.balanceOf(alice), 1, "position not burned on failed exercise");
        _checkLiveAccounting();
    }

    function test_direct_musd_transfer_is_uncredited() public {
        uint256 collateralBefore = series.collateral_balance_raw();
        vm.prank(alice);
        musd.transfer(address(series), WAD);
        _assertEq(series.collateral_balance_raw(), collateralBefore, "donation not credited");
        _assertEq(series.excess_raw(), 0, "donation creates no capacity");
        _assertTrue(musd.balanceOf(address(series)) > collateralBefore, "donation is stranded surplus");
        _checkSolvency();
    }

    function test_transferFrom_without_allowance_reverts() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.expectRevert(RosterBtcPutSeries.InsufficientAllowance.selector);
        vm.prank(spender);
        series.transferFrom(alice, bob, 1);
    }

    function test_transfer_at_maturity_reverts() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.prank(alice);
        series.approve(spender, 2);
        vm.warp(expiryTime);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.transfer(bob, 1);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(spender);
        series.transferFrom(alice, bob, 1);
    }

    function test_transfer_after_finalization_reverts() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.warp(expiryTime);
        series.expire();
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.transfer(bob, 1);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.transferFrom(alice, bob, 1);
    }

    function test_limbo_state() public {
        _deposit(3 * STRIKE_PER_LOT);
        _buy(alice, 3);
        uint256 collateralAtMaturity = series.collateral_balance_raw();
        vm.warp(expiryTime);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(writer);
        series.deposit(WAD);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(bob);
        series.purchase(1);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.exercise(1);
        vm.expectRevert(RosterBtcPutSeries.SeriesMatured.selector);
        vm.prank(alice);
        series.transfer(bob, 1);
        _assertTrue(!series.expired(), "not finalized yet");
        _assertEq(series.collateral_balance_raw(), collateralAtMaturity, "collateral held in limbo");
        _checkLiveAccounting();
        vm.prank(carol);
        series.expire();
        _assertTrue(series.expired(), "permissionless finalization");
    }

    function test_transfer_to_self_contract_reverts() public {
        _deposit(2 * STRIKE_PER_LOT);
        _buy(alice, 2);
        vm.expectRevert(RosterBtcPutSeries.InvalidRecipient.selector);
        vm.prank(alice);
        series.transfer(address(series), 1);
        vm.prank(alice);
        series.approve(spender, 1);
        vm.expectRevert(RosterBtcPutSeries.InvalidRecipient.selector);
        vm.prank(spender);
        series.transferFrom(alice, address(series), 1);
        _assertEq(series.balanceOf(alice), 2, "position unchanged");
        _assertEq(series.reserved_raw(), 2 * STRIKE_PER_LOT, "reserve unchanged");
    }

    function test_reentrancy_callback_blocked_by_guard_zero_allowance() public {
        (RosterBtcPutSeries s, MockERC20 m, CallbackERC20 btc) = _newCallbackSeries();
        vm.prank(writer);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(s), type(uint256).max);
        btc.mint(alice, 10 * WAD);
        vm.prank(writer);
        s.deposit(5 * WAD);
        vm.prank(alice);
        s.purchase(2);
        bytes memory payload = abi.encodeWithSelector(s.transferFrom.selector, alice, attacker, 1);
        btc.configureCallback(address(s), address(s), payload, false);
        vm.prank(alice);
        s.exercise(1);
        _assertTrue(!btc.lastCallbackSucceeded(), "callback transferFrom blocked");
        _assertEq(
            btc.lastCallbackRevertSelector(),
            bytes4(keccak256("ReentrancyGuardReentrantCall()")),
            "guard runs before allowance"
        );
        _assertEq(s.allowance(alice, address(btc)), 0, "zero allowance remains zero");
        _assertEq(s.balanceOf(alice), 1, "outer burn only");
        _assertEq(s.balanceOf(attacker), 0, "attacker gets none");
        _assertEq(s.active_lots(), 1, "active lots");
        _assertEq(s.reserved_raw(), STRIKE_PER_LOT, "reserve");
    }

    function test_reentrancy_callback_blocked_by_guard_nonzero_allowance() public {
        (RosterBtcPutSeries s, MockERC20 m, CallbackERC20 btc) = _newCallbackSeries();
        vm.prank(writer);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(s), type(uint256).max);
        btc.mint(alice, 10 * WAD);
        vm.prank(writer);
        s.deposit(5 * WAD);
        vm.prank(alice);
        s.purchase(2);
        vm.prank(alice);
        s.approve(address(btc), 1);
        bytes memory payload = abi.encodeWithSelector(s.transferFrom.selector, alice, attacker, 1);
        btc.configureCallback(address(s), address(s), payload, false);
        vm.prank(alice);
        s.exercise(1);
        _assertTrue(!btc.lastCallbackSucceeded(), "callback transferFrom blocked");
        _assertEq(
            btc.lastCallbackRevertSelector(),
            bytes4(keccak256("ReentrancyGuardReentrantCall()")),
            "guard runs before allowance"
        );
        _assertEq(s.allowance(alice, address(btc)), 1, "allowance not consumed by failed callback");
        _assertEq(s.balanceOf(alice), 1, "outer burn only");
        _assertEq(s.balanceOf(attacker), 0, "attacker gets none");
        _assertEq(s.active_lots(), 1, "active lots");
    }

    function test_reentrancy_callback_bubbled_reverts_outer() public {
        (RosterBtcPutSeries s, MockERC20 m, CallbackERC20 btc) = _newCallbackSeries();
        vm.prank(writer);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        m.approve(address(s), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(s), type(uint256).max);
        btc.mint(alice, 10 * WAD);
        vm.prank(writer);
        s.deposit(5 * WAD);
        vm.prank(alice);
        s.purchase(2);
        bytes memory payload = abi.encodeWithSelector(s.transferFrom.selector, alice, attacker, 1);
        btc.configureCallback(address(s), address(s), payload, true);
        uint256 alicePosBefore = s.balanceOf(alice);
        uint256 supplyBefore = s.totalSupply();
        uint256 reserveBefore = s.reserved_raw();
        uint256 collateralBefore = s.collateral_balance_raw();
        uint256 btcAliceBefore = btc.balanceOf(alice);
        uint256 btcWriterBefore = btc.balanceOf(writer);
        uint256 btcAllowanceBefore = btc.allowance(alice, address(s));
        vm.expectRevert(bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        vm.prank(alice);
        s.exercise(1);
        _assertEq(s.balanceOf(alice), alicePosBefore, "position reverted");
        _assertEq(s.totalSupply(), supplyBefore, "supply reverted");
        _assertEq(s.active_lots(), 2, "active lots reverted");
        _assertEq(s.reserved_raw(), reserveBefore, "reserve reverted");
        _assertEq(s.collateral_balance_raw(), collateralBefore, "collateral reverted");
        _assertEq(btc.balanceOf(alice), btcAliceBefore, "btc debit reverted");
        _assertEq(btc.balanceOf(writer), btcWriterBefore, "btc credit reverted");
        _assertEq(btc.allowance(alice, address(s)), btcAllowanceBefore, "btc allowance reverted");
    }

    function test_constructor_wrong_btc_decimals_reverts() public {
        MockERC20 badBtc = new MockERC20("Bad BTC", "BADBTC", 8);
        vm.expectRevert(abi.encodeWithSelector(RosterBtcPutSeries.InvalidTokenDecimals.selector, address(badBtc), 8));
        new RosterBtcPutSeries(writer, address(musd), address(badBtc), K_RAW, PREMIUM_PER_LOT, expiryTime, "X", "X");
    }

    function test_fee_on_transfer_musd_is_rejected_atomically() public {
        FeeOnTransferERC20 feeMUSD = new FeeOnTransferERC20("Fee MUSD", "fMUSD", 18);
        feeMUSD.mint(writer, 100 * WAD);
        RosterBtcPutSeries feeSeries = new RosterBtcPutSeries(
            writer, address(feeMUSD), address(btc), K_RAW, PREMIUM_PER_LOT, expiryTime, "Fee Test", "FEE"
        );
        vm.prank(writer);
        feeMUSD.approve(address(feeSeries), type(uint256).max);
        uint256 writerBefore = feeMUSD.balanceOf(writer);
        vm.expectRevert(abi.encodeWithSelector(RosterBtcPutSeries.UnexpectedTokenAmount.selector, address(feeMUSD)));
        vm.prank(writer);
        feeSeries.deposit(10 * WAD);
        _assertEq(feeSeries.total_deposited_raw(), 0, "failed deposit rolled accounting back");
        _assertEq(feeSeries.collateral_balance_raw(), 0, "no collateral credited");
        _assertEq(feeMUSD.balanceOf(address(feeSeries)), 0, "token movement reverted");
        _assertEq(feeMUSD.balanceOf(writer), writerBefore, "writer balance reverted");
    }

    function test_expiry_release_audit_identity() public {
        _deposit(10 * WAD);
        _buy(alice, 10);
        vm.prank(alice);
        series.exercise(2);
        vm.warp(expiryTime);
        series.expire();
        _assertEq(
            series.total_deposited_raw() - series.total_payouts_raw() - series.expiry_release_raw(),
            0,
            "post expiry audit"
        );
    }

    function _newCallbackSeries() internal returns (RosterBtcPutSeries s, MockERC20 m, CallbackERC20 btc) {
        m = new MockERC20("MUSD callback test", "mMUSD", 18);
        btc = new CallbackERC20("BTC callback test", "cBTC", 18);
        s = new RosterBtcPutSeries(
            writer,
            address(m),
            address(btc),
            K_RAW,
            PREMIUM_PER_LOT,
            block.timestamp + 30 days,
            "Callback Put Series",
            "CBPUT"
        );
        m.mint(writer, 1_000_000 * WAD);
        m.mint(alice, 1_000_000 * WAD);
    }
}
