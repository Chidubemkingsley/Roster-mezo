// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/RosterBtcPutSeries.sol

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(IERC20.transfer, (to, value))
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(IERC20.transferFrom, (from, to, value))
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeCall(IERC20.approve, (spender, value))
        );
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success) {
            if (returndata.length != 0) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
            revert SafeERC20FailedOperation(address(token));
        }
        if (
            returndata.length != 0 &&
            (returndata.length < 32 || !abi.decode(returndata, (bool)))
        ) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}

abstract contract ReentrancyGuard {
    error ReentrancyGuardReentrantCall();
    uint256 private _status = 1;

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

/// @title Roster Mezo BTC Put Series (Wave 2)
/// @notice Fixed-series, physically settled, MUSD-collateralized put on Mezo BTC.
/// @dev One token = one 1e-6 BTC lot. The ERC-20 position ledger is internal to this contract.
///      A protocol fee (in basis points) is collected from the buyer at purchase time and
///      forwarded immediately to the immutable feeRecipient. The fee does not reduce
///      the writer's collateral or the reserve backing active positions.
///      Mechanism demonstration only; this contract has not been professionally audited.
contract RosterBtcPutSeries is IERC20Metadata, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error IdenticalTokenAddresses();
    error InvalidTokenDecimals(address token, uint8 actualDecimals);
    error InvalidExpiry();
    error InvalidStrike();
    error InvalidPremium();
    error InvalidFeeBps();
    error OnlyWriter();
    error WriterCannotPurchase();
    error WriterCannotExercise();
    error SeriesMatured();
    error NotMatured();
    error InvalidQuantity();
    error InsufficientExcess();
    error InsufficientPositionTokens();
    error InsufficientBtcBalance();
    error InsufficientBtcAllowance();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidRecipient();
    error InvalidSender();
    error NoPremiumToWithdraw();
    error AmountOverflow();
    error UnexpectedTokenAmount(address token);

    address public immutable writer;
    IERC20Metadata public immutable musd;
    IERC20Metadata public immutable btc;
    uint256 public immutable K_raw;
    uint256 public immutable strike_per_lot_raw;
    uint256 public immutable premium_per_lot_raw;
    uint256 public immutable expiry;
    uint256 public constant LOT_SIZE_RAW = 1e12; // 1e-6 BTC, assuming 18 decimals
    uint256 public constant MAX_FEE_BPS = 500; // 5% hard cap

    /// @notice Protocol fee in basis points charged on buyer premium at purchase.
    uint256 public immutable feeBps;
    /// @notice Recipient of the protocol fee; set once at deployment.
    address public immutable feeRecipient;
    /// @notice Cumulative protocol fees collected across all purchases.
    uint256 public total_fees_collected_raw;

    string private _seriesName;
    string private _seriesSymbol;

    uint256 public total_deposited_raw;
    uint256 public total_payouts_raw;
    uint256 public expiry_release_raw;
    uint256 public collateral_balance_raw;
    uint256 public reserved_raw;
    uint256 public excess_raw;
    uint256 public premium_balance_raw;
    uint256 public active_lots;
    uint256 private _totalSupply;
    bool public expired;

    mapping(address account => uint256 amount) private _balances;
    mapping(address account => mapping(address spender => uint256 amount))
        private _allowances;

    event WriterDeposited(address indexed writer, uint256 amount);
    event Purchased(
        address indexed buyer,
        uint256 lots,
        uint256 premium,
        uint256 reserve
    );
    event Exercised(
        address indexed holder,
        uint256 lots,
        uint256 btcAmount,
        uint256 musdPayout
    );
    event SeriesExpired(address indexed writer, uint256 releasedCollateral);
    event PremiumWithdrawn(address indexed writer, uint256 amount);
    event ProtocolFeeCollected(address indexed feeRecipient, uint256 amount);

    constructor(
        address writer_,
        address musd_,
        address btc_,
        uint256 K_raw_,
        uint256 premium_per_lot_raw_,
        uint256 expiry_,
        string memory name_,
        string memory symbol_,
        address feeRecipient_,
        uint256 feeBps_
    ) {
        if (
            writer_ == address(0) || musd_ == address(0) || btc_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (feeRecipient_ == address(0)) revert ZeroAddress();
        if (musd_ == btc_) revert IdenticalTokenAddresses();
        if (expiry_ <= block.timestamp) revert InvalidExpiry();
        if (K_raw_ == 0 || K_raw_ % 1e6 != 0 || K_raw_ / 1e6 == 0)
            revert InvalidStrike();
        if (premium_per_lot_raw_ == 0) revert InvalidPremium();
        if (feeBps_ > MAX_FEE_BPS) revert InvalidFeeBps();

        uint8 musdDecimals = IERC20Metadata(musd_).decimals();
        if (musdDecimals != 18)
            revert InvalidTokenDecimals(musd_, musdDecimals);
        uint8 btcDecimals = IERC20Metadata(btc_).decimals();
        if (btcDecimals != 18) revert InvalidTokenDecimals(btc_, btcDecimals);

        writer = writer_;
        musd = IERC20Metadata(musd_);
        btc = IERC20Metadata(btc_);
        K_raw = K_raw_;
        strike_per_lot_raw = K_raw_ / 1e6;
        premium_per_lot_raw = premium_per_lot_raw_;
        expiry = expiry_;
        _seriesName = name_;
        _seriesSymbol = symbol_;
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
    }

    // Internal position ledger exposed through the ERC-20 ABI. Protocol-specific restrictions
    // prohibit transfer to writer, address(this), or the zero address, and freeze transfers at maturity.
    function name() external view override returns (string memory) {
        return _seriesName;
    }

    function symbol() external view override returns (string memory) {
        return _seriesSymbol;
    }

    function decimals() external pure override returns (uint8) {
        return 0;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @dev Deliberately unguarded: approval changes allowance only, not position balances.
    function approve(
        address spender,
        uint256 value
    ) external override returns (bool) {
        if (spender == address(0)) revert InvalidRecipient();
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(
        address to,
        uint256 value
    ) external override nonReentrant returns (bool) {
        _checkTransferAllowed(to);
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override nonReentrant returns (bool) {
        _checkTransferAllowed(to);
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                _allowances[from][msg.sender] = currentAllowance - value;
            }
            emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    function _checkTransferAllowed(address to) private view {
        if (to == address(0) || to == writer || to == address(this))
            revert InvalidRecipient();
        if (expired || block.timestamp >= expiry) revert SeriesMatured();
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert InvalidSender();
        if (to == address(0)) revert InvalidRecipient();
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert InsufficientBalance();
        unchecked {
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) private {
        _totalSupply += value;
        _balances[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) private {
        uint256 balance = _balances[from];
        if (balance < value) revert InsufficientPositionTokens();
        unchecked {
            _balances[from] = balance - value;
            _totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    function deposit(uint256 amount) external nonReentrant {
        if (msg.sender != writer) revert OnlyWriter();
        _requireLive();
        if (amount == 0) revert InvalidQuantity();
        uint256 writerBalanceBefore = musd.balanceOf(msg.sender);
        uint256 contractBalanceBefore = musd.balanceOf(address(this));
        total_deposited_raw += amount;
        collateral_balance_raw += amount;
        excess_raw += amount;
        IERC20(address(musd)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        _requireExactDecrease(
            IERC20(address(musd)),
            msg.sender,
            writerBalanceBefore,
            amount
        );
        _requireExactIncrease(
            IERC20(address(musd)),
            address(this),
            contractBalanceBefore,
            amount
        );
        emit WriterDeposited(msg.sender, amount);
    }

    function purchase(uint256 lots) external nonReentrant {
        _requireLive();
        if (msg.sender == writer) revert WriterCannotPurchase();
        if (lots == 0) revert InvalidQuantity();

        uint256 premium = _checkedMul(lots, premium_per_lot_raw);
        uint256 reserveNeeded = _checkedMul(lots, strike_per_lot_raw);
        if (premium == 0) revert InvalidPremium();
        if (reserveNeeded > excess_raw) revert InsufficientExcess();

        // Protocol fee is calculated on top of the writer premium. The buyer pays
        // premium + fee; only premium enters the series reserve liability.
        uint256 feeAmount = feeBps == 0 ? 0 : (premium * feeBps) / 10_000;
        uint256 totalCharge = premium + feeAmount;

        uint256 buyerMUSDBefore = musd.balanceOf(msg.sender);
        uint256 contractMUSDBefore = musd.balanceOf(address(this));

        excess_raw -= reserveNeeded;
        reserved_raw += reserveNeeded;
        active_lots += lots;
        premium_balance_raw += premium;
        _mint(msg.sender, lots);

        // Pull total charge from buyer in one transfer.
        IERC20(address(musd)).safeTransferFrom(
            msg.sender,
            address(this),
            totalCharge
        );
        _requireExactDecrease(
            IERC20(address(musd)),
            msg.sender,
            buyerMUSDBefore,
            totalCharge
        );
        _requireExactIncrease(
            IERC20(address(musd)),
            address(this),
            contractMUSDBefore,
            totalCharge
        );

        // Forward the protocol fee immediately so it is never mixed with collateral.
        if (feeAmount != 0) {
            uint256 recipientBefore = musd.balanceOf(feeRecipient);
            IERC20(address(musd)).safeTransfer(feeRecipient, feeAmount);
            _requireExactIncrease(
                IERC20(address(musd)),
                feeRecipient,
                recipientBefore,
                feeAmount
            );
            total_fees_collected_raw += feeAmount;
            emit ProtocolFeeCollected(feeRecipient, feeAmount);
        }

        emit Purchased(msg.sender, lots, premium, reserveNeeded);
    }

    function exercise(uint256 lots) external nonReentrant {
        _requireLive();
        if (msg.sender == writer) revert WriterCannotExercise();
        if (lots == 0) revert InvalidQuantity();
        if (lots > active_lots || _balances[msg.sender] < lots)
            revert InsufficientPositionTokens();

        uint256 btcAmount = _checkedMul(lots, LOT_SIZE_RAW);
        uint256 payout = _checkedMul(lots, strike_per_lot_raw);
        uint256 holderBtcBefore = btc.balanceOf(msg.sender);
        uint256 writerBtcBefore = btc.balanceOf(writer);
        if (holderBtcBefore < btcAmount) revert InsufficientBtcBalance();
        if (btc.allowance(msg.sender, address(this)) < btcAmount)
            revert InsufficientBtcAllowance();
        uint256 holderMUSDBefore = musd.balanceOf(msg.sender);
        uint256 contractMUSDBefore = musd.balanceOf(address(this));

        _burn(msg.sender, lots);
        collateral_balance_raw -= payout;
        reserved_raw -= payout;
        active_lots -= lots;
        total_payouts_raw += payout;

        IERC20(address(btc)).safeTransferFrom(msg.sender, writer, btcAmount);
        _requireExactDecrease(
            IERC20(address(btc)),
            msg.sender,
            holderBtcBefore,
            btcAmount
        );
        _requireExactIncrease(
            IERC20(address(btc)),
            writer,
            writerBtcBefore,
            btcAmount
        );
        IERC20(address(musd)).safeTransfer(msg.sender, payout);
        _requireExactDecrease(
            IERC20(address(musd)),
            address(this),
            contractMUSDBefore,
            payout
        );
        _requireExactIncrease(
            IERC20(address(musd)),
            msg.sender,
            holderMUSDBefore,
            payout
        );
        emit Exercised(msg.sender, lots, btcAmount, payout);
    }

    /// @notice Permissionless lazy finalization after maturity. Repeated calls are no-ops.
    function expire() external nonReentrant {
        if (block.timestamp < expiry) revert NotMatured();
        if (expired) return;
        expired = true;
        uint256 releaseAmount = collateral_balance_raw;
        uint256 contractMUSDBefore = musd.balanceOf(address(this));
        uint256 writerMUSDBefore = musd.balanceOf(writer);
        expiry_release_raw = releaseAmount;
        collateral_balance_raw = 0;
        reserved_raw = 0;
        excess_raw = 0;
        active_lots = 0;
        // _totalSupply and balances remain unchanged; expired tokens are worthless and frozen.
        if (releaseAmount != 0) {
            IERC20(address(musd)).safeTransfer(writer, releaseAmount);
            _requireExactDecrease(
                IERC20(address(musd)),
                address(this),
                contractMUSDBefore,
                releaseAmount
            );
            _requireExactIncrease(
                IERC20(address(musd)),
                writer,
                writerMUSDBefore,
                releaseAmount
            );
        }
        emit SeriesExpired(writer, releaseAmount);
    }

    function withdrawPremium() external nonReentrant {
        if (msg.sender != writer) revert OnlyWriter();
        uint256 amount = premium_balance_raw;
        if (amount == 0) revert NoPremiumToWithdraw();
        uint256 contractMUSDBefore = musd.balanceOf(address(this));
        uint256 writerMUSDBefore = musd.balanceOf(writer);
        premium_balance_raw = 0;
        IERC20(address(musd)).safeTransfer(writer, amount);
        _requireExactDecrease(
            IERC20(address(musd)),
            address(this),
            contractMUSDBefore,
            amount
        );
        _requireExactIncrease(
            IERC20(address(musd)),
            writer,
            writerMUSDBefore,
            amount
        );
        emit PremiumWithdrawn(writer, amount);
    }

    function _requireLive() private view {
        if (expired || block.timestamp >= expiry) revert SeriesMatured();
    }

    function _checkedMul(
        uint256 a,
        uint256 b
    ) private pure returns (uint256 c) {
        if (a != 0 && b > type(uint256).max / a) revert AmountOverflow();
        c = a * b;
    }

    function _requireExactIncrease(
        IERC20 token,
        address account,
        uint256 beforeBalance,
        uint256 amount
    ) private view {
        uint256 afterBalance = token.balanceOf(account);
        if (
            afterBalance < beforeBalance ||
            afterBalance - beforeBalance != amount
        ) {
            revert UnexpectedTokenAmount(address(token));
        }
    }

    function _requireExactDecrease(
        IERC20 token,
        address account,
        uint256 beforeBalance,
        uint256 amount
    ) private view {
        uint256 afterBalance = token.balanceOf(account);
        if (
            afterBalance > beforeBalance ||
            beforeBalance - afterBalance != amount
        ) {
            revert UnexpectedTokenAmount(address(token));
        }
    }
}

// src/RosterTroveWriter.sol

interface IBorrowerOperations {
    function openTrove(
        uint256 debtAmount,
        address upperHint,
        address lowerHint
    ) external payable;
    function addColl(address upperHint, address lowerHint) external payable;
    function withdrawColl(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external;
    function withdrawMUSD(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external;
    function repayMUSD(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external;
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
    function getCurrentICR(
        address borrower,
        uint256 price
    ) external view returns (uint256);
    /// @dev Returns the Total Collateral Ratio of the system (sum of all trove collateral
    ///      over total MUSD supply). Mezo enters Recovery Mode when TCR < CCR (150%).
    function getTCR(uint256 price) external view returns (uint256);
    /// @dev True when the system is in Recovery Mode (TCR < CCR).
    function checkRecoveryMode(uint256 price) external view returns (bool);
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
    /// @notice Reverts when Mezo is in Recovery Mode and the operation would increase
    ///         system indebtedness. The writer is long BTC through the trove and must
    ///         not worsen the system's collateral ratio during stressed conditions.
    error RecoveryModeActive(uint256 tcr);

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
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
    event RecoveryModeBlocked(uint256 tcr);

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
            owner_ == address(0) ||
            borrowerOperations_ == address(0) ||
            troveManager_ == address(0) ||
            priceFeed_ == address(0) ||
            musd_ == address(0) ||
            btc_ == address(0)
        ) revert ZeroAddress();
        if (
            borrowerOperations_.code.length == 0 ||
            troveManager_.code.length == 0 ||
            priceFeed_.code.length == 0
        ) {
            revert NotAContract();
        }
        if (minICR_ < MIN_ALLOWED_ICR || minICR_ > MAX_ALLOWED_ICR)
            revert InvalidMinICR();

        address activePool_ = IBorrowerOperations(borrowerOperations_)
            .activePool();
        address collSurplusPool_ = IBorrowerOperations(borrowerOperations_)
            .collSurplusPool();
        if (activePool_ == address(0) || collSurplusPool_ == address(0))
            revert ZeroAddress();
        if (activePool_.code.length == 0 || collSurplusPool_.code.length == 0)
            revert NotAContract();

        owner = owner_;
        borrowerOperations = IBorrowerOperations(borrowerOperations_);
        troveManager = ITroveManager(troveManager_);
        priceFeed = IMezoPriceFeed(priceFeed_);
        musd = IERC20(musd_);
        btc = IERC20(btc_);
        activePool = activePool_;
        collSurplusPool = collSurplusPool_;
        musdGasCompensation = IBorrowerOperations(borrowerOperations_)
            .MUSD_GAS_COMPENSATION();
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
        if (seriesAddress == address(0) || seriesAddress.code.length == 0)
            revert InvalidSeries();
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
        if (newMinICR < MIN_ALLOWED_ICR || newMinICR > MAX_ALLOWED_ICR)
            revert InvalidMinICR();
        minICR = newMinICR;
        emit MinICRUpdated(newMinICR);
    }

    /// @notice Open a Mezo trove with native BTC, borrow MUSD, and deposit part of it
    ///         into this vault's series. Interest and debt remain the owner's obligation.
    function openAndFund(
        uint256 debtAmount,
        uint256 seriesDeposit,
        address upperHint,
        address lowerHint
    ) external payable onlyOwner nonReentrant {
        _requireSeriesBound();
        if (troveManager.getTroveStatus(address(this)) == TROVE_STATUS_ACTIVE) {
            revert TroveAlreadyOpen();
        }
        if (msg.value == 0) revert NoCollateral();
        if (seriesDeposit == 0 || seriesDeposit > debtAmount)
            revert InvalidDeposit();

        // Opening a trove increases system debt. Block during Recovery Mode so the
        // vault cannot worsen a system-level collateral crisis.
        _requireNotRecoveryMode();

        borrowerOperations.openTrove{value: msg.value}(
            debtAmount,
            upperHint,
            lowerHint
        );

        if (musd.balanceOf(address(this)) < seriesDeposit)
            revert InsufficientMUSD();
        _fundSeries(seriesDeposit);
        _checkICR();
        emit TroveOpened(msg.value, debtAmount, seriesDeposit);
    }

    function addCollateral(
        address upperHint,
        address lowerHint
    ) external payable onlyOwner nonReentrant {
        _requireActiveTrove();
        if (msg.value == 0) revert NoCollateral();
        borrowerOperations.addColl{value: msg.value}(upperHint, lowerHint);
        emit CollateralAdded(msg.value);
    }

    function withdrawCollateral(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external onlyOwner nonReentrant {
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

    function borrowMore(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external onlyOwner nonReentrant {
        _requireActiveTrove();
        if (amount == 0) revert NothingToWithdraw();
        // Borrowing more increases system debt. Block during Recovery Mode.
        _requireNotRecoveryMode();
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
    function repay(
        uint256 amount,
        address upperHint,
        address lowerHint
    ) external onlyOwner nonReentrant {
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
    function claimCollateral()
        external
        onlyOwner
        nonReentrant
        returns (uint256 received)
    {
        uint256 before = address(this).balance;
        borrowerOperations.claimCollateral();
        received = address(this).balance - before;
        if (received == 0) revert NothingToWithdraw();
        _sendNative(owner, received);
        emit CollateralSurplusClaimed(received);
    }

    /// @notice Withdraw premium earned by the series and forward it to the owner.
    function withdrawPremium()
        external
        onlyOwner
        nonReentrant
        returns (uint256 amount)
    {
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
    function finalize()
        external
        onlyOwner
        nonReentrant
        returns (uint256 expiryRelease, uint256 premium)
    {
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
    function withdrawBtc(
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
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
        return
            troveManager.getTroveStatus(address(this)) == TROVE_STATUS_ACTIVE;
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
        returns (
            uint256 collateral,
            uint256 debt,
            uint256 icr,
            uint256 price,
            uint8 status
        )
    {
        price = priceFeed.fetchPrice();
        collateral = troveManager.getTroveColl(address(this));
        debt = troveManager.getTroveDebt(address(this));
        status = troveManager.getTroveStatus(address(this));
        icr = debt == 0
            ? type(uint256).max
            : troveManager.getCurrentICR(address(this), price);
    }

    function seriesState()
        external
        view
        returns (
            uint256 collateral,
            uint256 premium,
            uint256 activeLots,
            bool expired
        )
    {
        if (!seriesBound) {
            return (0, 0, 0, false);
        }
        collateral = series.collateral_balance_raw();
        premium = series.premium_balance_raw();
        activeLots = series.active_lots();
        expired = series.expired();
    }

    /// @notice Current system Total Collateral Ratio. Falls below 1.5e18 in Recovery Mode.
    function systemTCR() external view returns (uint256) {
        return troveManager.getTCR(priceFeed.fetchPrice());
    }

    /// @notice True when the Mezo system is in Recovery Mode (TCR < 150%).
    ///         During Recovery Mode, openAndFund and borrowMore are blocked.
    function isInRecoveryMode() external view returns (bool) {
        return troveManager.checkRecoveryMode(priceFeed.fetchPrice());
    }

    function _requireSeriesBound() private view {
        if (!seriesBound) revert SeriesNotBound();
    }

    function _requireActiveTrove() private view {
        uint8 status = troveManager.getTroveStatus(address(this));
        if (status != TROVE_STATUS_ACTIVE) revert TroveNotActive(status);
    }

    function _checkICR() private view {
        uint256 icr = troveManager.getCurrentICR(
            address(this),
            priceFeed.fetchPrice()
        );
        if (icr < minICR) revert ICRTooLow(icr);
    }

    /// @dev Reverts with RecoveryModeActive when the system TCR is below Mezo's CCR.
    ///      This protects the protocol by blocking new debt that would deepen a system crisis.
    ///      Repayments, collateral additions, and closures are explicitly allowed during
    ///      Recovery Mode — they all improve or preserve the system TCR.
    function _requireNotRecoveryMode() private view {
        uint256 price = priceFeed.fetchPrice();
        bool inRecoveryMode = troveManager.checkRecoveryMode(price);
        if (inRecoveryMode) {
            uint256 tcr = troveManager.getTCR(price);
            revert RecoveryModeActive(tcr);
        }
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
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }
}
