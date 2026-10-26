// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, ReentrancyGuard, RosterBtcPutSeries, SafeERC20} from "./RosterBtcPutSeries.sol";

interface IBorrowerOperations {
    function openTrove(uint256 debtAmount, address upperHint, address lowerHint) external payable;
    function addColl(address upperHint, address lowerHint) external payable;
    function withdrawColl(uint256 amount, address upperHint, address lowerHint) external;
    function withdrawMUSD(uint256 amount, address upperHint, address lowerHint) external;
    function repayMUSD(uint256 amount, address upperHint, address lowerHint) external;
    function closeTrove() external;
    function claimCollateral() external;
    function activePool() external view returns (address);
    function collSurplusPool() external view returns (address);
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
}

interface ITroveManager {
    function updateSystemAndTroveInterest(address borrower) external;
    function getTroveStatus(address borrower) external view returns (uint8);
    function getTroveDebt(address borrower) external view returns (uint256);
    function getTroveColl(address borrower) external view returns (uint256);
    function getCurrentICR(address borrower, uint256 price) external view returns (uint256);
}

interface IMezoPriceFeed {
    function fetchPrice() external view returns (uint256);
}

/// @title Roster Trove Writer
/// @notice A separate, per-series vault bound to one factory-created Roster series.
///         It opens a Mezo trove with native BTC, borrows MUSD, and deposits that MUSD
///         into the series as writer collateral.
/// @dev Native BTC trove collateral and the series' ERC-20 BTC underlying are separate
///      assets. This vault never converts one into the other. Trove debt, interest, and
///      liquidation risk belong to the owner. The series reserve is a separate bucket and
///      remains fully collateralized even if the trove is liquidated. Exercised ERC-20 BTC
///      is held for the owner and withdrawn explicitly with withdrawBtc().
contract RosterTroveWriter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant TROVE_STATUS_ACTIVE = 1;
    uint256 private constant MIN_ALLOWED_ICR = 1.2e18;
    uint256 private constant MAX_ALLOWED_ICR = 5e18;

    error ZeroAddress();
    error NotAContract();
    error OnlyOwner();
    error SeriesNotBound();
    error SeriesAlreadyBound();
    error InvalidSeries();
    error TroveAlreadyOpen();
    error TroveNotActive(uint8 status);
    error NoCollateral();
    error InvalidDeposit();
    error InvalidMinICR();
    error ICRTooLow(uint256 icr);
    error InsufficientMUSD();
    error InsufficientIdleMUSD(uint256 requested, uint256 available);
    error NoPremium();
    error NothingToWithdraw();
    error NativeTransferFailed();
    error UnexpectedNativeAmount();
    error UnexpectedNativeSender();
    error NoDebt();

    address public owner;
    IBorrowerOperations public immutable borrowerOperations;
    ITroveManager public immutable troveManager;
    IMezoPriceFeed public immutable priceFeed;
    IERC20 public immutable musd;
    IERC20 public immutable btc;
    address public immutable activePool;
    address public immutable collSurplusPool;
    uint256 public immutable musdGasCompensation;

    RosterBtcPutSeries public series;
    bool public seriesBound;

    /// @notice Application-level minimum ICR. Always strictly above Mezo's 110% MCR.
    uint256 public minICR;
    uint256 public totalDepositedToSeries;
    uint256 public premiumForwarded;
    uint256 public expiryForwarded;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MinICRUpdated(uint256 minICR);
    event SeriesBound(address indexed series);
    event TroveOpened(uint256 collateral, uint256 debt, uint256 seriesDeposit);
    event CollateralAdded(uint256 amount);
    event CollateralWithdrawn(uint256 amount);
    event MUSDWithdrawnFromTrove(uint256 amount);
    event SeriesFunded(uint256 amount);
    event DebtRepaid(uint256 amount);
    event PremiumForwarded(uint256 amount);
    event ExpiryReleaseForwarded(uint256 amount);
    event TroveClosed(uint256 collateralReturned);
    event CollateralSurplusClaimed(uint256 amount);
    event BtcWithdrawn(address indexed to, uint256 amount);
    event IdleMUSDWithdrawn(uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        address owner_,
        address borrowerOperations_,
        address troveManager_,
        address priceFeed_,
        address musd_,
        address btc_,
        uint256 minICR_
    ) {
        if (
            owner_ == address(0) || borrowerOperations_ == address(0) || troveManager_ == address(0)
                || priceFeed_ == address(0) || musd_ == address(0) || btc_ == address(0)
        ) revert ZeroAddress();
        if (borrowerOperations_.code.length == 0 || troveManager_.code.length == 0 || priceFeed_.code.length == 0) {
            revert NotAContract();
        }
        if (minICR_ < MIN_ALLOWED_ICR || minICR_ > MAX_ALLOWED_ICR) revert InvalidMinICR();

        address activePool_ = IBorrowerOperations(borrowerOperations_).activePool();
        address collSurplusPool_ = IBorrowerOperations(borrowerOperations_).collSurplusPool();
        if (activePool_ == address(0) || collSurplusPool_ == address(0)) revert ZeroAddress();
        if (activePool_.code.length == 0 || collSurplusPool_.code.length == 0) revert NotAContract();

        owner = owner_;
        borrowerOperations = IBorrowerOperations(borrowerOperations_);
        troveManager = ITroveManager(troveManager_);
        priceFeed = IMezoPriceFeed(priceFeed_);
        musd = IERC20(musd_);
        btc = IERC20(btc_);
        activePool = activePool_;
        collSurplusPool = collSurplusPool_;
        musdGasCompensation = IBorrowerOperations(borrowerOperations_).MUSD_GAS_COMPENSATION();
        minICR = minICR_;
    }

    /// @dev Mezo returns collateral from ActivePool (closure/withdrawal) and
    ///      CollSurplusPool (surplus recovery), not from BorrowerOperations itself.
    ///      Accept exactly those two resolved pool addresses; reject every other sender.
    receive() external payable {
        if (msg.sender != activePool && msg.sender != collSurplusPool) {
            revert UnexpectedNativeSender();
        }
    }

    /// @notice Bind this vault to its factory-created series once. The series must name
    ///         this vault as writer and use the same MUSD and BTC assets.
    function bindSeries(address seriesAddress) external onlyOwner {
        if (seriesBound) revert SeriesAlreadyBound();
        if (seriesAddress == address(0) || seriesAddress.code.length == 0) revert InvalidSeries();
        RosterBtcPutSeries candidate = RosterBtcPutSeries(seriesAddress);
        if (candidate.writer() != address(this)) revert InvalidSeries();
        if (address(candidate.musd()) != address(musd)) revert InvalidSeries();
        if (address(candidate.btc()) != address(btc)) revert InvalidSeries();
        series = candidate;
        seriesBound = true;
        emit SeriesBound(seriesAddress);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setMinICR(uint256 newMinICR) external onlyOwner {
        if (newMinICR < MIN_ALLOWED_ICR || newMinICR > MAX_ALLOWED_ICR) revert InvalidMinICR();
        minICR = newMinICR;
        emit MinICRUpdated(newMinICR);
    }

    /// @notice Open a Mezo trove with native BTC, borrow MUSD, and deposit part of it
    ///         into this vault's series. Interest and debt remain the owner's obligation.
    function openAndFund(uint256 debtAmount, uint256 seriesDeposit, address upperHint, address lowerHint)
        external
        payable
        onlyOwner
        nonReentrant
    {
        _requireSeriesBound();
        if (troveManager.getTroveStatus(address(this)) == TROVE_STATUS_ACTIVE) {
            revert TroveAlreadyOpen();
        }
        if (msg.value == 0) revert NoCollateral();
        if (seriesDeposit == 0 || seriesDeposit > debtAmount) revert InvalidDeposit();

        borrowerOperations.openTrove{value: msg.value}(debtAmount, upperHint, lowerHint);

        if (musd.balanceOf(address(this)) < seriesDeposit) revert InsufficientMUSD();
        _fundSeries(seriesDeposit);
        _checkICR();
        emit TroveOpened(msg.value, debtAmount, seriesDeposit);
    }

    function addCollateral(address upperHint, address lowerHint) external payable onlyOwner nonReentrant {
        _requireActiveTrove();
        if (msg.value == 0) revert NoCollateral();
        borrowerOperations.addColl{value: msg.value}(upperHint, lowerHint);
        emit CollateralAdded(msg.value);
    }

    function withdrawCollateral(uint256 amount, address upperHint, address lowerHint) external onlyOwner nonReentrant {
        _requireActiveTrove();
        if (amount == 0) revert NothingToWithdraw();
        uint256 before = address(this).balance;
        borrowerOperations.withdrawColl(amount, upperHint, lowerHint);
        uint256 received = address(this).balance - before;
        if (received != amount) revert UnexpectedNativeAmount();
        _checkICR();
        _sendNative(owner, received);
        emit CollateralWithdrawn(amount);
    }

    function borrowMore(uint256 amount, address upperHint, address lowerHint) external onlyOwner nonReentrant {
        _requireActiveTrove();
        if (amount == 0) revert NothingToWithdraw();
        borrowerOperations.withdrawMUSD(amount, upperHint, lowerHint);
        _checkICR();
        emit MUSDWithdrawnFromTrove(amount);
    }

    /// @notice Move idle borrowed MUSD into the series as additional writer collateral.
    function depositToSeries(uint256 amount) external onlyOwner nonReentrant {
        _requireSeriesBound();
        if (amount == 0) revert InvalidDeposit();
        uint256 available = idleMUSD();
        if (amount > available) revert InsufficientIdleMUSD(amount, available);
        _fundSeries(amount);
    }

    /// @notice Partial repayment. Mezo burns MUSD directly from this vault.
    function repay(uint256 amount, address upperHint, address lowerHint) external onlyOwner nonReentrant {
        _requireActiveTrove();
        if (amount == 0) revert NothingToWithdraw();
        musd.safeTransferFrom(msg.sender, address(this), amount);
        borrowerOperations.repayMUSD(amount, upperHint, lowerHint);
        emit DebtRepaid(amount);
    }

    /// @notice Full closure. Mezo burns the remaining debt minus gas compensation from
    ///         this vault and returns native BTC collateral. Pulls only the MUSD shortfall
    ///         from the owner and preserves any unforwarded series expiry release.
    function closeTrove() external onlyOwner nonReentrant {
        _requireActiveTrove();
        troveManager.updateSystemAndTroveInterest(address(this));
        uint256 debt = troveManager.getTroveDebt(address(this));
        if (debt <= musdGasCompensation) revert NoDebt();
        uint256 required = debt - musdGasCompensation;

        uint256 balance = musd.balanceOf(address(this));
        uint256 reserved = _reservedSeriesProceeds();
        uint256 idle = balance > reserved ? balance - reserved : 0;
        if (idle < required) {
            musd.safeTransferFrom(owner, address(this), required - idle);
        }

        uint256 before = address(this).balance;
        borrowerOperations.closeTrove();
        uint256 received = address(this).balance - before;
        _sendNative(owner, received);
        emit TroveClosed(received);
    }

    /// @notice Recover collateral surplus after a redemption or liquidation.
    function claimCollateral() external onlyOwner nonReentrant returns (uint256 received) {
        uint256 before = address(this).balance;
        borrowerOperations.claimCollateral();
        received = address(this).balance - before;
        if (received == 0) revert NothingToWithdraw();
        _sendNative(owner, received);
        emit CollateralSurplusClaimed(received);
    }

    /// @notice Withdraw premium earned by the series and forward it to the owner.
    function withdrawPremium() external onlyOwner nonReentrant returns (uint256 amount) {
        _requireSeriesBound();
        amount = series.premium_balance_raw();
        if (amount == 0) revert NoPremium();
        series.withdrawPremium();
        premiumForwarded += amount;
        musd.safeTransfer(owner, amount);
        emit PremiumForwarded(amount);
    }

    /// @notice Finalize an expired series. Tracks releases so collateral already sent by
    ///         a third-party expire() call is still forwarded exactly once.
    function finalize() external onlyOwner nonReentrant returns (uint256 expiryRelease, uint256 premium) {
        _requireSeriesBound();
        series.expire();

        uint256 release = series.expiry_release_raw();
        if (release > expiryForwarded) {
            expiryRelease = release - expiryForwarded;
            expiryForwarded = release;
            musd.safeTransfer(owner, expiryRelease);
            emit ExpiryReleaseForwarded(expiryRelease);
        }

        premium = series.premium_balance_raw();
        if (premium != 0) {
            series.withdrawPremium();
            premiumForwarded += premium;
            musd.safeTransfer(owner, premium);
            emit PremiumForwarded(premium);
        }
    }

    /// @notice Withdraw ERC-20 BTC received from physical exercise. Native trove BTC is
    ///         separate and leaves through withdrawCollateral() or closeTrove().
    function withdrawBtc(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert NothingToWithdraw();
        btc.safeTransfer(to, amount);
        emit BtcWithdrawn(to, amount);
    }

    /// @notice Withdraw MUSD that is not reserved for an already-released series expiry.
    function withdrawIdleMUSD(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert NothingToWithdraw();
        uint256 available = idleMUSD();
        if (amount > available) revert InsufficientIdleMUSD(amount, available);
        musd.safeTransfer(owner, amount);
        emit IdleMUSDWithdrawn(amount);
    }

    function isTroveActive() public view returns (bool) {
        return troveManager.getTroveStatus(address(this)) == TROVE_STATUS_ACTIVE;
    }

    /// @notice MUSD held by the vault that is not reserved for series expiry collateral.
    function idleMUSD() public view returns (uint256) {
        uint256 balance = musd.balanceOf(address(this));
        uint256 reserved = _reservedSeriesProceeds();
        return balance > reserved ? balance - reserved : 0;
    }

    /// @notice Series expiry MUSD already received but not yet forwarded to the owner.
    function reservedMUSD() external view returns (uint256) {
        return _reservedSeriesProceeds();
    }

    function troveInfo()
        external
        view
        returns (uint256 collateral, uint256 debt, uint256 icr, uint256 price, uint8 status)
    {
        price = priceFeed.fetchPrice();
        collateral = troveManager.getTroveColl(address(this));
        debt = troveManager.getTroveDebt(address(this));
        status = troveManager.getTroveStatus(address(this));
        icr = debt == 0 ? type(uint256).max : troveManager.getCurrentICR(address(this), price);
    }

    function seriesState()
        external
        view
        returns (uint256 collateral, uint256 premium, uint256 activeLots, bool expired)
    {
        if (!seriesBound) {
            return (0, 0, 0, false);
        }
        collateral = series.collateral_balance_raw();
        premium = series.premium_balance_raw();
        activeLots = series.active_lots();
        expired = series.expired();
    }

    function _requireSeriesBound() private view {
        if (!seriesBound) revert SeriesNotBound();
    }

    function _requireActiveTrove() private view {
        uint8 status = troveManager.getTroveStatus(address(this));
        if (status != TROVE_STATUS_ACTIVE) revert TroveNotActive(status);
    }

    function _checkICR() private view {
        uint256 icr = troveManager.getCurrentICR(address(this), priceFeed.fetchPrice());
        if (icr < minICR) revert ICRTooLow(icr);
    }

    function _reservedSeriesProceeds() private view returns (uint256) {
        if (!seriesBound) return 0;
        uint256 release = series.expiry_release_raw();
        return release > expiryForwarded ? release - expiryForwarded : 0;
    }

    function _fundSeries(uint256 amount) private {
        musd.safeApprove(address(series), amount);
        series.deposit(amount);
        totalDepositedToSeries += amount;
        emit SeriesFunded(amount);
    }

    function _sendNative(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }
}
