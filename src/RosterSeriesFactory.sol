// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RosterBtcPutSeries} from "./RosterBtcPutSeries.sol";

/// @title Roster Series Factory
/// @notice Permissionless registry for fixed-series BTC puts on Mezo.
/// @dev The factory fixes only the MUSD and BTC assets. Writers compete on strike,
///      premium, expiry, and branding by deploying independent, immutable series.
///      A factory deployment does not prove that a series is funded or demand exists.
contract RosterSeriesFactory {
    error ZeroAddress();
    error IdenticalTokenAddresses();

    address public immutable musd;
    address public immutable btc;

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

    constructor(address musd_, address btc_) {
        if (musd_ == address(0) || btc_ == address(0)) revert ZeroAddress();
        if (musd_ == btc_) revert IdenticalTokenAddresses();
        musd = musd_;
        btc = btc_;
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
        series = new RosterBtcPutSeries(writer, musd, btc, K_raw, premiumPerLot_raw, expiry, name, symbol);
        address seriesAddress = address(series);
        _series.push(seriesAddress);
        isSeries[seriesAddress] = true;
        emit SeriesCreated(seriesAddress, writer, K_raw, premiumPerLot_raw, expiry, name, symbol);
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
