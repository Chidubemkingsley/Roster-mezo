// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RosterBtcPutSeries} from "./RosterBtcPutSeries.sol";

/// @title Roster Series Factory
/// @notice Permissionless registry for fixed-series BTC puts on Mezo.
/// @dev The factory fixes the MUSD, BTC, and fee-recipient assets. Writers compete on
///      strike, premium, expiry, and branding by deploying independent, immutable series.
///      A factory deployment does not prove that a series is funded or demand exists.
///      All series created through this factory share the same feeRecipient and feeBps
///      set at construction. Zero feeBps is valid (fee-free mode for testnet).
contract RosterSeriesFactory {
    error ZeroAddress();
    error IdenticalTokenAddresses();
    error InvalidFeeBps();

    address public immutable musd;
    address public immutable btc;
    /// @notice Protocol fee basis points applied to every series created through this factory.
    uint256 public immutable feeBps;
    /// @notice Receives the per-purchase protocol fee from every series created here.
    address public immutable feeRecipient;

    address[] private _series;
    mapping(address series => bool known) public isSeries;

    event SeriesCreated(
        address indexed series,
        address indexed writer,
        uint256 strikeRaw,
        uint256 premiumPerLotRaw,
        uint256 expiry,
        string name,
        string symbol
    );

    constructor(
        address musd_,
        address btc_,
        address feeRecipient_,
        uint256 feeBps_
    ) {
        if (
            musd_ == address(0) ||
            btc_ == address(0) ||
            feeRecipient_ == address(0)
        ) revert ZeroAddress();
        if (musd_ == btc_) revert IdenticalTokenAddresses();
        if (feeBps_ > 500) revert InvalidFeeBps(); // 5% hard cap, matches RosterBtcPutSeries.MAX_FEE_BPS
        musd = musd_;
        btc = btc_;
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
    }

    /// @notice Deploy a new immutable series. Anyone may create one; the named writer
    ///         must separately approve and deposit MUSD before buyers can purchase.
    function createSeries(
        address writer,
        uint256 K_raw,
        uint256 premiumPerLot_raw,
        uint256 expiry,
        string calldata name,
        string calldata symbol
    ) external returns (RosterBtcPutSeries series) {
        series = new RosterBtcPutSeries(
            writer,
            musd,
            btc,
            K_raw,
            premiumPerLot_raw,
            expiry,
            name,
            symbol,
            feeRecipient,
            feeBps
        );
        address seriesAddress = address(series);
        _series.push(seriesAddress);
        isSeries[seriesAddress] = true;
        emit SeriesCreated(
            seriesAddress,
            writer,
            K_raw,
            premiumPerLot_raw,
            expiry,
            name,
            symbol
        );
    }

    function seriesCount() external view returns (uint256) {
        return _series.length;
    }

    function seriesAt(uint256 index) external view returns (address) {
        return _series[index];
    }

    function allSeries() external view returns (address[] memory) {
        return _series;
    }
}
