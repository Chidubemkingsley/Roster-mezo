// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, ReentrancyGuard, RosterBtcPutSeries, SafeERC20} from "./RosterBtcPutSeries.sol";
import {RosterSeriesFactory} from "./RosterSeriesFactory.sol";

/// @title Roster Secondary Ask Book
/// @notice Escrowed, partially fillable secondary listings for Roster position tokens.
/// @dev Sellers escrow position lots; buyers pay MUSD directly to the seller. The book
///      supplies a public ask side and therefore observable secondary price discovery.
///      It is intentionally not a matching engine and has no bids, fees, or keepers.
///      Listings must be cancelled before maturity because the series freezes transfers.
///
///      A listing is accepted only if the series is registered by the configured factory
///      and its MUSD asset matches the book's MUSD. This prevents a buyer from paying in
///      one MUSD-like token for a position that settles in another.
contract RosterOrderBook is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidFactory();
    error InvalidSeries();
    error SeriesNotRegistered();
    error SeriesMismatchedMUSD();
    error InvalidQuantity();
    error InvalidPrice();
    error SeriesNotLive();
    error UnknownListing();
    error ListingNotActive();
    error NotSeller();
    error InsufficientListing();
    error AmountOverflow();

    struct Listing {
        address seller;
        RosterBtcPutSeries series;
        uint256 pricePerLot;
        uint256 remaining;
        bool active;
    }

    IERC20 public immutable musd;
    RosterSeriesFactory public immutable factory;
    uint256 public nextListingId = 1;
    mapping(uint256 listingId => Listing listing) public listings;

    event Listed(
        uint256 indexed listingId, address indexed seller, address indexed series, uint256 lots, uint256 pricePerLot
    );
    event Filled(uint256 indexed listingId, address indexed buyer, uint256 lots, uint256 musdPaid);
    event Cancelled(uint256 indexed listingId, uint256 lotsReturned);

    constructor(address musd_, address factory_) {
        if (musd_ == address(0) || factory_ == address(0)) revert ZeroAddress();
        if (factory_.code.length == 0) revert InvalidFactory();
        if (RosterSeriesFactory(factory_).musd() != musd_) revert InvalidFactory();
        musd = IERC20(musd_);
        factory = RosterSeriesFactory(factory_);
    }

    /// @notice Escrow position lots and publish an ask. Requires prior series approval.
    function list(address seriesAddress, uint256 lots, uint256 pricePerLot)
        external
        nonReentrant
        returns (uint256 listingId)
    {
        if (seriesAddress == address(0)) revert ZeroAddress();
        if (seriesAddress.code.length == 0) revert InvalidSeries();
        if (lots == 0) revert InvalidQuantity();
        if (pricePerLot == 0) revert InvalidPrice();

        RosterBtcPutSeries series = RosterBtcPutSeries(seriesAddress);

        // The series must settle in this book's MUSD and be a factory-created series.
        // Check the asset first so a mismatched series cannot be mistaken for a typo.
        if (address(series.musd()) != address(musd)) revert SeriesMismatchedMUSD();
        if (!factory.isSeries(seriesAddress)) revert SeriesNotRegistered();
        if (series.expired() || block.timestamp >= series.expiry()) revert SeriesNotLive();

        IERC20(address(series)).safeTransferFrom(msg.sender, address(this), lots);

        listingId = nextListingId++;
        listings[listingId] =
            Listing({seller: msg.sender, series: series, pricePerLot: pricePerLot, remaining: lots, active: true});

        emit Listed(listingId, msg.sender, seriesAddress, lots, pricePerLot);
    }

    /// @notice Buy all or part of a listing at the seller's ask.
    function fill(uint256 listingId, uint256 lots) external nonReentrant {
        if (lots == 0) revert InvalidQuantity();
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert UnknownListing();
        if (!listing.active) revert ListingNotActive();
        if (lots > listing.remaining) revert InsufficientListing();
        if (listing.series.expired() || block.timestamp >= listing.series.expiry()) {
            revert SeriesNotLive();
        }
        if (lots > type(uint256).max / listing.pricePerLot) revert AmountOverflow();

        uint256 cost = lots * listing.pricePerLot;
        listing.remaining -= lots;
        if (listing.remaining == 0) listing.active = false;

        musd.safeTransferFrom(msg.sender, listing.seller, cost);
        IERC20(address(listing.series)).safeTransfer(msg.sender, lots);

        emit Filled(listingId, msg.sender, lots, cost);
    }

    /// @notice Return remaining escrowed lots to the seller. Must be called before maturity.
    function cancel(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert UnknownListing();
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();
        if (listing.series.expired() || block.timestamp >= listing.series.expiry()) {
            revert SeriesNotLive();
        }

        uint256 lotsReturned = listing.remaining;
        listing.remaining = 0;
        listing.active = false;
        IERC20(address(listing.series)).safeTransfer(msg.sender, lotsReturned);

        emit Cancelled(listingId, lotsReturned);
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
}
