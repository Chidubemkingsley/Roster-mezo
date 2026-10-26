// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.transfer, (to, value)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.transferFrom, (from, to, value)));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(IERC20.approve, (spender, value)));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success) {
            if (returndata.length != 0) {
                assembly { revert(add(returndata, 32), mload(returndata)) }
            }
            revert SafeERC20FailedOperation(address(token));
        }
        if (returndata.length != 0 && (returndata.length < 32 || !abi.decode(returndata, (bool)))) {
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

/// @title Roster Mezo BTC Put Series (Wave 1)
/// @notice Fixed-series, physically settled, MUSD-collateralized put on Mezo BTC.
/// @dev One token = one 1e-6 BTC lot. The ERC-20 position ledger is internal to this contract.
///      Mechanism demonstration only; this contract has not been professionally audited.
contract RosterBtcPutSeries is IERC20Metadata, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error IdenticalTokenAddresses();
    error InvalidTokenDecimals(address token, uint8 actualDecimals);
    error InvalidExpiry();
    error InvalidStrike();
    error InvalidPremium();
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
    mapping(address account => mapping(address spender => uint256 amount)) private _allowances;

    event WriterDeposited(address indexed writer, uint256 amount);
    event Purchased(address indexed buyer, uint256 lots, uint256 premium, uint256 reserve);
    event Exercised(address indexed holder, uint256 lots, uint256 btcAmount, uint256 musdPayout);
    event SeriesExpired(address indexed writer, uint256 releasedCollateral);
    event PremiumWithdrawn(address indexed writer, uint256 amount);

    constructor(
        address writer_,
        address musd_,
        address btc_,
        uint256 K_raw_,
        uint256 premium_per_lot_raw_,
        uint256 expiry_,
        string memory name_,
        string memory symbol_
    ) {
        if (writer_ == address(0) || musd_ == address(0) || btc_ == address(0)) {
            revert ZeroAddress();
        }
        if (musd_ == btc_) revert IdenticalTokenAddresses();
        if (expiry_ <= block.timestamp) revert InvalidExpiry();
        if (K_raw_ == 0 || K_raw_ % 1e6 != 0 || K_raw_ / 1e6 == 0) revert InvalidStrike();
        if (premium_per_lot_raw_ == 0) revert InvalidPremium();

        uint8 musdDecimals = IERC20Metadata(musd_).decimals();
        if (musdDecimals != 18) revert InvalidTokenDecimals(musd_, musdDecimals);
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

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @dev Deliberately unguarded: approval changes allowance only, not position balances.
    function approve(address spender, uint256 value) external override returns (bool) {
        if (spender == address(0)) revert InvalidRecipient();
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external override nonReentrant returns (bool) {
        _checkTransferAllowed(to);
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override nonReentrant returns (bool) {
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
        if (to == address(0) || to == writer || to == address(this)) revert InvalidRecipient();
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
        IERC20(address(musd)).safeTransferFrom(msg.sender, address(this), amount);
        _requireExactDecrease(IERC20(address(musd)), msg.sender, writerBalanceBefore, amount);
        _requireExactIncrease(IERC20(address(musd)), address(this), contractBalanceBefore, amount);
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
        uint256 buyerMUSDBefore = musd.balanceOf(msg.sender);
        uint256 contractMUSDBefore = musd.balanceOf(address(this));

        excess_raw -= reserveNeeded;
        reserved_raw += reserveNeeded;
        active_lots += lots;
        premium_balance_raw += premium;
        _mint(msg.sender, lots);
        IERC20(address(musd)).safeTransferFrom(msg.sender, address(this), premium);
        _requireExactDecrease(IERC20(address(musd)), msg.sender, buyerMUSDBefore, premium);
        _requireExactIncrease(IERC20(address(musd)), address(this), contractMUSDBefore, premium);
        emit Purchased(msg.sender, lots, premium, reserveNeeded);
    }

    function exercise(uint256 lots) external nonReentrant {
        _requireLive();
        if (msg.sender == writer) revert WriterCannotExercise();
        if (lots == 0) revert InvalidQuantity();
        if (lots > active_lots || _balances[msg.sender] < lots) revert InsufficientPositionTokens();

        uint256 btcAmount = _checkedMul(lots, LOT_SIZE_RAW);
        uint256 payout = _checkedMul(lots, strike_per_lot_raw);
        uint256 holderBtcBefore = btc.balanceOf(msg.sender);
        uint256 writerBtcBefore = btc.balanceOf(writer);
        if (holderBtcBefore < btcAmount) revert InsufficientBtcBalance();
        if (btc.allowance(msg.sender, address(this)) < btcAmount) revert InsufficientBtcAllowance();
        uint256 holderMUSDBefore = musd.balanceOf(msg.sender);
        uint256 contractMUSDBefore = musd.balanceOf(address(this));

        _burn(msg.sender, lots);
        collateral_balance_raw -= payout;
        reserved_raw -= payout;
        active_lots -= lots;
        total_payouts_raw += payout;

        IERC20(address(btc)).safeTransferFrom(msg.sender, writer, btcAmount);
        _requireExactDecrease(IERC20(address(btc)), msg.sender, holderBtcBefore, btcAmount);
        _requireExactIncrease(IERC20(address(btc)), writer, writerBtcBefore, btcAmount);
        IERC20(address(musd)).safeTransfer(msg.sender, payout);
        _requireExactDecrease(IERC20(address(musd)), address(this), contractMUSDBefore, payout);
        _requireExactIncrease(IERC20(address(musd)), msg.sender, holderMUSDBefore, payout);
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
            _requireExactDecrease(IERC20(address(musd)), address(this), contractMUSDBefore, releaseAmount);
            _requireExactIncrease(IERC20(address(musd)), writer, writerMUSDBefore, releaseAmount);
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
        _requireExactDecrease(IERC20(address(musd)), address(this), contractMUSDBefore, amount);
        _requireExactIncrease(IERC20(address(musd)), writer, writerMUSDBefore, amount);
        emit PremiumWithdrawn(writer, amount);
    }

    function _requireLive() private view {
        if (expired || block.timestamp >= expiry) revert SeriesMatured();
    }

    function _checkedMul(uint256 a, uint256 b) private pure returns (uint256 c) {
        if (a != 0 && b > type(uint256).max / a) revert AmountOverflow();
        c = a * b;
    }

    function _requireExactIncrease(IERC20 token, address account, uint256 beforeBalance, uint256 amount) private view {
        uint256 afterBalance = token.balanceOf(account);
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) {
            revert UnexpectedTokenAmount(address(token));
        }
    }

    function _requireExactDecrease(IERC20 token, address account, uint256 beforeBalance, uint256 amount) private view {
        uint256 afterBalance = token.balanceOf(account);
        if (afterBalance > beforeBalance || beforeBalance - afterBalance != amount) {
            revert UnexpectedTokenAmount(address(token));
        }
    }
}
