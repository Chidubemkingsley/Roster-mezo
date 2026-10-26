// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase, Vm} from "./TestBase.sol";
import {RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @dev Stateful action handler. Fuzzed transfer recipients are always from this closed actor set.
contract SeriesHandler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    RosterBtcPutSeries public immutable series;
    MockERC20 public immutable musd;
    MockERC20 public immutable btc;
    address public immutable writer;
    address[] private _actors;

    uint256 public successfulCalls;
    uint256 public failedCalls;
    bool public finalizationSnapshotSet;
    uint256 public supplyAtFinalization;
    uint256 public balanceSumAtFinalization;

    constructor(
        RosterBtcPutSeries series_,
        MockERC20 musd_,
        MockERC20 btc_,
        address writer_,
        address[] memory actors_
    ) {
        series = series_;
        musd = musd_;
        btc = btc_;
        writer = writer_;
        for (uint256 i; i < actors_.length; ++i) {
            _actors.push(actors_[i]);
        }
    }

    function actors() external view returns (address[] memory) {
        return _actors;
    }

    function actionDeposit(uint256 rawAmount) external {
        uint256 amount = (rawAmount % (100 * 1e18)) + 1;
        _callAs(writer, abi.encodeWithSelector(series.deposit.selector, amount));
    }

    function actionPurchase(uint256 rawLots, uint256 rawActor) external {
        uint256 lots = (rawLots % 100) + 1;
        address buyer = _actor(rawActor);
        _callAs(buyer, abi.encodeWithSelector(series.purchase.selector, lots));
    }

    function actionExercise(uint256 rawLots, uint256 rawActor) external {
        uint256 lots = (rawLots % 100) + 1;
        address holder = _actor(rawActor);
        _callAs(holder, abi.encodeWithSelector(series.exercise.selector, lots));
    }

    function actionTransfer(uint256 rawLots, uint256 rawFrom, uint256 rawTo) external {
        uint256 lots = (rawLots % 100) + 1;
        address from = _actor(rawFrom);
        address to = _actor(rawTo);
        _callAs(from, abi.encodeWithSelector(series.transfer.selector, to, lots));
    }

    function actionApprove(uint256 rawAmount, uint256 rawOwner, uint256 rawSpender) external {
        uint256 amount = (rawAmount % 100) + 1;
        address owner = _actor(rawOwner);
        address spender = _actor(rawSpender);
        _callAs(owner, abi.encodeWithSelector(series.approve.selector, spender, amount));
    }

    function actionTransferFrom(uint256 rawLots, uint256 rawFrom, uint256 rawSpender, uint256 rawTo) external {
        uint256 lots = (rawLots % 100) + 1;
        address from = _actor(rawFrom);
        address spender = _actor(rawSpender);
        address to = _actor(rawTo);
        _callAs(spender, abi.encodeWithSelector(series.transferFrom.selector, from, to, lots));
    }

    function actionWithdrawPremium() external {
        _callAs(writer, abi.encodeWithSelector(series.withdrawPremium.selector));
    }

    function actionMature() external {
        vm.warp(series.expiry());
    }

    function actionFinalize() external {
        _callAs(address(this), abi.encodeWithSelector(series.expire.selector));
        if (series.expired() && !finalizationSnapshotSet) {
            finalizationSnapshotSet = true;
            supplyAtFinalization = series.totalSupply();
            balanceSumAtFinalization = _positionBalanceSum();
        }
    }

    function sumPositionBalances() external view returns (uint256) {
        return _positionBalanceSum();
    }

    function _positionBalanceSum() internal view returns (uint256 total) {
        for (uint256 i; i < _actors.length; ++i) {
            total += series.balanceOf(_actors[i]);
        }
    }

    function _actor(uint256 index) internal view returns (address) {
        return _actors[index % _actors.length];
    }

    function _callAs(address caller, bytes memory callData) internal {
        vm.prank(caller);
        (bool ok,) = address(series).call(callData);
        if (ok) ++successfulCalls;
        else ++failedCalls;
    }
}

contract SeriesInvariantTest is TestBase {
    SeriesHandler internal handler;
    address[] internal fuzzActors;

    function setUp() public override {
        super.setUp();
        fuzzActors.push(alice);
        fuzzActors.push(bob);
        fuzzActors.push(carol);
        handler = new SeriesHandler(series, musd, btc, writer, fuzzActors);
    }

    /// @dev Foundry invariant target discovery: only the action handler is fuzzed.
    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_collateral_split() public view {
        _assertEq(series.collateral_balance_raw(), series.reserved_raw() + series.excess_raw(), "collateral split");
    }

    function invariant_reserve_matches_active_lots() public view {
        _assertEq(series.reserved_raw(), series.active_lots() * series.strike_per_lot_raw(), "reserve/active lots");
    }

    function invariant_supply_equals_active_lots_until_finalization() public view {
        if (!series.expired()) {
            _assertEq(series.totalSupply(), series.active_lots(), "supply/active lots before finalization");
        }
    }

    function invariant_finalized_counters_and_supply() public view {
        if (series.expired()) {
            _assertEq(series.collateral_balance_raw(), 0, "finalized collateral");
            _assertEq(series.reserved_raw(), 0, "finalized reserve");
            _assertEq(series.excess_raw(), 0, "finalized excess");
            _assertEq(series.active_lots(), 0, "finalized active lots");
            _assertEq(series.totalSupply(), handler.sumPositionBalances(), "finalized supply equals tracked balances");
            if (handler.finalizationSnapshotSet()) {
                _assertEq(series.totalSupply(), handler.supplyAtFinalization(), "supply constant after finalization");
                _assertEq(
                    handler.sumPositionBalances(),
                    handler.balanceSumAtFinalization(),
                    "balances constant after finalization"
                );
            }
        }
    }

    function invariant_audit_identity() public view {
        _assertEq(
            series.total_deposited_raw() - series.total_payouts_raw() - series.expiry_release_raw(),
            series.collateral_balance_raw(),
            "audit identity"
        );
    }

    function invariant_musd_solvency_at_action_boundaries() public view {
        _assertTrue(
            musd.balanceOf(address(series)) >= series.collateral_balance_raw() + series.premium_balance_raw(),
            "MUSD covers recorded liabilities after completed calls"
        );
    }
}
