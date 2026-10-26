// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {MockERC20} from "../src/MockERC20.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
    function deal(address account, uint256 newBalance) external;
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant writer = address(0xA11CE);
    address internal constant alice = address(0xB0B);
    address internal constant bob = address(0xCAFE);
    address internal constant carol = address(0xD00D);
    address internal constant attacker = address(0xBAD);
    address internal constant spender = address(0x515E);

    uint256 internal constant K_RAW = 80_000 * 1e18;
    uint256 internal constant STRIKE_PER_LOT = 80_000 * 1e12; // 0.08 MUSD / lot
    uint256 internal constant PREMIUM_PER_LOT = 1e15; // 0.001 MUSD / lot
    uint256 internal constant WAD = 1e18;

    MockERC20 internal musd;
    MockERC20 internal btc;
    RosterBtcPutSeries internal series;
    uint256 internal expiryTime;

    function setUp() public virtual {
        musd = new MockERC20("Mezo USD", "MUSD", 18);
        btc = new MockERC20("BTC", "BTC", 18);
        expiryTime = block.timestamp + 30 days;
        series = new RosterBtcPutSeries(
            writer,
            address(musd),
            address(btc),
            K_RAW,
            PREMIUM_PER_LOT,
            expiryTime,
            "Roster Mezo BTC Put Series",
            "RBTC-PUT"
        );

        musd.mint(writer, 1_000_000 * WAD);
        musd.mint(alice, 1_000_000 * WAD);
        musd.mint(bob, 1_000_000 * WAD);
        musd.mint(carol, 1_000_000 * WAD);
        btc.mint(alice, 1_000 * WAD);
        btc.mint(bob, 1_000 * WAD);
        btc.mint(carol, 1_000 * WAD);

        vm.prank(writer);
        musd.approve(address(series), type(uint256).max);
        vm.prank(alice);
        musd.approve(address(series), type(uint256).max);
        vm.prank(bob);
        musd.approve(address(series), type(uint256).max);
        vm.prank(carol);
        musd.approve(address(series), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(series), type(uint256).max);
        vm.prank(bob);
        btc.approve(address(series), type(uint256).max);
        vm.prank(carol);
        btc.approve(address(series), type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(writer);
        series.deposit(amount);
    }

    function _buy(address buyer, uint256 lots) internal {
        vm.prank(buyer);
        series.purchase(lots);
    }

    function _checkLiveAccounting() internal view {
        _assertEq(series.collateral_balance_raw(), series.reserved_raw() + series.excess_raw(), "collateral split");
        _assertEq(series.reserved_raw(), series.active_lots() * series.strike_per_lot_raw(), "reserve formula");
        _assertEq(series.totalSupply(), series.active_lots(), "live supply formula");
        _checkAudit();
        _checkSolvency();
    }

    function _checkAudit() internal view {
        _assertEq(
            series.total_deposited_raw() - series.total_payouts_raw() - series.expiry_release_raw(),
            series.collateral_balance_raw(),
            "audit identity"
        );
    }

    function _checkSolvency() internal view {
        uint256 liabilities = series.collateral_balance_raw() + series.premium_balance_raw();
        _assertTrue(musd.balanceOf(address(series)) >= liabilities, "MUSD solvency");
    }

    function _assertEq(uint256 a, uint256 b, string memory reason) internal pure {
        require(a == b, reason);
    }

    function _assertEq(address a, address b, string memory reason) internal pure {
        require(a == b, reason);
    }

    function _assertEq(bytes4 a, bytes4 b, string memory reason) internal pure {
        require(a == b, reason);
    }

    function _assertEq(string memory a, string memory b, string memory reason) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), reason);
    }

    function _assertTrue(bool condition, string memory reason) internal pure {
        require(condition, reason);
    }
}
