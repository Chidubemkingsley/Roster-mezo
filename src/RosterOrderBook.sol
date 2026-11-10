// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, ReentrancyGuard, RosterBtcPutSeries, SafeERC20} from "./RosterBtcPutSeries.sol";
import {RosterSeriesFactory} from "./RosterSeriesFactory.sol";

/// @title Roster Secondary Ask Book
/// @notice Escrowed, partially fillable secondary listings for Roster position tokens.
/// @dev Sellers escrow position lots; buyers pay MUSD directly to the seller minus a
///      protocol fill fee (in basis points) that is forwarded to the feeRecipient.
///      The book supplies a public ask side and therefore observable secondary price
///      discovery. It is intentionally not a matching engine and has no bids or keepers.
///      Listings must be cancelled before maturity because the series freezes transfers.
///
///      A listing is accepted only if the series is registered by the configured factory
///      and its MUSD asset matches the book's MUSD. This prevents a buyer from paying in
///      one MUSD-like token for a position that settles in another.
///
///      Fill fee:
///        buyer pays  = lots × pricePerLot
///        seller gets = lots × pricePerLot × (10_000 - fillFeeBps) / 10_000
///        fee gets    = buyer pays - seller gets
///      The fill fee accrues in this contract and is swept by the feeRecipient.
contract RosterOrderBook is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_FILL_FEE_BPS = 500; // 5% hard cap

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
    error InvalidFeeBps();
    error NothingToSweep();

    struct Listing {
        address seller;
        RosterBtcPutSeries series;
        uint256 pricePerLot;
        uint256 remaining;
        bool active;
    }

    IERC20 public immutable musd;
    RosterSeriesFactory public immutable factory;
    /// @notice Protocol fill fee in basis points, taken from the gross fill amount.
    uint256 public immutable fillFeeBps;
    /// @notice Receives accrued fill fees; sweepable by anyone (permissionless flush).
    address public immutable feeRecipient;

    uint256 public nextListingId = 1;
    /// @notice Total protocol fees accrued but not yet swept.
    uint256 public accruedFees;

    mapping(uint256 listingId => Listing listing) public listings;

    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed series,
        uint256 lots,
        uint256 pricePerLot
    );
    event Filled(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 lots,
        uint256 grossPaid,
        uint256 feeCharged
    );
    event Cancelled(uint256 indexed listingId, uint256 lotsReturned);
    event FeeSwept(address indexed feeRecipient, uint256 amount);

    constructor(
        address musd_,
        address factory_,
        address feeRecipient_,
        uint256 fillFeeBps_
    ) {
        if (
            musd_ == address(0) ||
            factory_ == address(0) ||
            feeRecipient_ == address(0)
        ) revert ZeroAddress();
        if (factory_.code.length == 0) revert InvalidFactory();
        if (RosterSeriesFactory(factory_).musd() != musd_)
            revert InvalidFactory();
        if (fillFeeBps_ > MAX_FILL_FEE_BPS) revert InvalidFeeBps();
        musd = IERC20(musd_);
        factory = RosterSeriesFactory(factory_);
        feeRecipient = feeRecipient_;
        fillFeeBps = fillFeeBps_;
    }

    /// @notice Escrow position lots and publish an ask. Requires prior series approval.
    function list(
        address seriesAddress,
        uint256 lots,
        uint256 pricePerLot
    ) external nonReentrant returns (uint256 listingId) {
        if (seriesAddress == address(0)) revert ZeroAddress();
        if (seriesAddress.code.length == 0) revert InvalidSeries();
        if (lots == 0) revert InvalidQuantity();
        if (pricePerLot == 0) revert InvalidPrice();

        RosterBtcPutSeries series = RosterBtcPutSeries(seriesAddress);

        // The series must settle in this book's MUSD and be a factory-created series.
        // Check the asset first so a mismatched series cannot be mistaken for a typo.
        if (address(series.musd()) != address(musd))
            revert SeriesMismatchedMUSD();
        if (!factory.isSeries(seriesAddress)) revert SeriesNotRegistered();
        if (series.expired() || block.timestamp >= series.expiry())
            revert SeriesNotLive();

        IERC20(address(series)).safeTransferFrom(
            msg.sender,
            address(this),
            lots
        );

        listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            series: series,
            pricePerLot: pricePerLot,
            remaining: lots,
            active: true
        });

        emit Listed(listingId, msg.sender, seriesAddress, lots, pricePerLot);
    }

    /// @notice Buy all or part of a listing at the seller's ask.
    /// @dev    Buyer pays the gross amount. The fill fee is deducted before forwarding
    ///         to the seller and held in this contract until swept.
    function fill(uint256 listingId, uint256 lots) external nonReentrant {
        if (lots == 0) revert InvalidQuantity();
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert UnknownListing();
        if (!listing.active) revert ListingNotActive();
        if (lots > listing.remaining) revert InsufficientListing();
        if (
            listing.series.expired() ||
            block.timestamp >= listing.series.expiry()
        ) {
            revert SeriesNotLive();
        }
        if (lots > type(uint256).max / listing.pricePerLot)
            revert AmountOverflow();

        uint256 grossCost = lots * listing.pricePerLot;
        uint256 feeCharged = fillFeeBps == 0
            ? 0
            : (grossCost * fillFeeBps) / 10_000;
        uint256 sellerProceeds = grossCost - feeCharged;

        listing.remaining -= lots;
        if (listing.remaining == 0) listing.active = false;

        // Pull gross from buyer.
        musd.safeTransferFrom(msg.sender, address(this), grossCost);
        // Forward net to seller immediately.
        musd.safeTransfer(listing.seller, sellerProceeds);
        // Accrue fee for later sweep.
        if (feeCharged != 0) {
            accruedFees += feeCharged;
        }
        IERC20(address(listing.series)).safeTransfer(msg.sender, lots);

        emit Filled(listingId, msg.sender, lots, grossCost, feeCharged);
    }

    /// @notice Return remaining escrowed lots to the seller. Must be called before maturity.
    function cancel(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller == address(0)) revert UnknownListing();
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();
        if (
            listing.series.expired() ||
            block.timestamp >= listing.series.expiry()
        ) {
            revert SeriesNotLive();
        }

        uint256 lotsReturned = listing.remaining;
        listing.remaining = 0;
        listing.active = false;
        IERC20(address(listing.series)).safeTransfer(msg.sender, lotsReturned);

        emit Cancelled(listingId, lotsReturned);
    }

    /// @notice Permissionlessly flush accrued fill fees to feeRecipient.
    function sweepFees() external nonReentrant {
        uint256 amount = accruedFees;
        if (amount == 0) revert NothingToSweep();
        accruedFees = 0;
        musd.safeTransfer(feeRecipient, amount);
        emit FeeSwept(feeRecipient, amount);
    }

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }
}
