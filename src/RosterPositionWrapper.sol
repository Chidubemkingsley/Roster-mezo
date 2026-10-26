// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20, ReentrancyGuard, RosterBtcPutSeries, SafeERC20} from "./RosterBtcPutSeries.sol";

/// @title Roster Position Wrapper
/// @notice Standard 18-decimal ERC-20 wrapper for one Roster series position.
/// @dev One wrapper unit of 1e18 represents one 1e-6 BTC lot. The wrapper custodies the
///      underlying series positions and gives external protocols a conventional ERC-20
///      plus a single-call exercise path. It does not change the series' settlement terms,
///      create leverage, or make the position redeemable for collateral. The underlying
///      series freezes transfers at expiry, so wrapper tokens have no value after expiry.
contract RosterPositionWrapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant UNIT = 1e18;

    error ZeroAddress();
    error InvalidSeries();
    error InvalidQuantity();
    error InvalidRecipient();
    error InvalidSender();
    error NotLive();
    error InsufficientBalance();
    error InsufficientAllowance();
    error UnexpectedTokenAmount(address token);

    RosterBtcPutSeries public immutable series;
    IERC20 public immutable musd;
    IERC20 public immutable btc;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposited(address indexed account, uint256 lots, uint256 wrapperAmount);
    event Withdrawn(address indexed account, uint256 lots, uint256 wrapperAmount);
    event Exercised(address indexed account, uint256 lots, uint256 btcAmount, uint256 musdPayout);

    constructor(RosterBtcPutSeries series_, string memory name_, string memory symbol_) {
        if (address(series_) == address(0)) revert ZeroAddress();
        if (address(series_).code.length == 0) revert InvalidSeries();
        series = series_;
        musd = IERC20(address(series_.musd()));
        btc = IERC20(address(series_.btc()));
        name = name_;
        symbol = symbol_;
    }

    /// @notice Wrap `lots` underlying position tokens. Requires prior series approval.
    function deposit(uint256 lots) external nonReentrant {
        if (lots == 0) revert InvalidQuantity();
        _requireLive();

        uint256 wrapperAmount = lots * UNIT;
        uint256 beforeBalance = series.balanceOf(address(this));
        if (!series.transferFrom(msg.sender, address(this), lots)) revert UnexpectedTokenAmount(address(series));
        if (series.balanceOf(address(this)) - beforeBalance != lots) revert UnexpectedTokenAmount(address(series));

        _mint(msg.sender, wrapperAmount);
        emit Deposited(msg.sender, lots, wrapperAmount);
    }

    /// @notice Unwrap `wrapperAmount` and receive the underlying position lots.
    function withdraw(uint256 wrapperAmount) external nonReentrant {
        _requireLotMultiple(wrapperAmount);
        _requireLive();

        uint256 lots = wrapperAmount / UNIT;
        _burn(msg.sender, wrapperAmount);
        if (!series.transfer(msg.sender, lots)) revert UnexpectedTokenAmount(address(series));
        emit Withdrawn(msg.sender, lots, wrapperAmount);
    }

    /// @notice Exercise wrapped positions. The caller supplies and approves ERC-20 BTC.
    ///         The series sends the BTC to its writer and the MUSD payout to this wrapper,
    ///         which forwards the payout to the caller.
    function exercise(uint256 wrapperAmount) external nonReentrant {
        _requireLotMultiple(wrapperAmount);
        _requireLive();

        uint256 lots = wrapperAmount / UNIT;
        uint256 btcAmount = lots * series.LOT_SIZE_RAW();
        uint256 musdPayout = lots * series.strike_per_lot_raw();

        _burn(msg.sender, wrapperAmount);

        uint256 btcBefore = btc.balanceOf(address(this));
        btc.safeTransferFrom(msg.sender, address(this), btcAmount);
        _requireExactIncrease(btc, address(this), btcBefore, btcAmount);

        if (btc.allowance(address(this), address(series)) != 0) {
            btc.safeApprove(address(series), 0);
        }
        btc.safeApprove(address(series), btcAmount);

        uint256 musdBefore = musd.balanceOf(address(this));
        series.exercise(lots);
        uint256 received = musd.balanceOf(address(this)) - musdBefore;
        if (received != musdPayout) revert UnexpectedTokenAmount(address(musd));

        btc.safeApprove(address(series), 0);
        musd.safeTransfer(msg.sender, received);
        emit Exercised(msg.sender, lots, btcAmount, received);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert InvalidRecipient();
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external nonReentrant returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external nonReentrant returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = currentAllowance - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
        return true;
    }

    /// @notice Underlying position lots held by this wrapper.
    function underlyingLots() external view returns (uint256) {
        return series.balanceOf(address(this));
    }

    /// @notice True while deposit, withdraw, and exercise are available.
    function isLive() public view returns (bool) {
        return !series.expired() && block.timestamp < series.expiry();
    }

    function _requireLive() private view {
        if (!isLive()) revert NotLive();
    }

    function _requireLotMultiple(uint256 wrapperAmount) private pure {
        if (wrapperAmount == 0 || wrapperAmount % UNIT != 0) revert InvalidQuantity();
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert InvalidSender();
        if (to == address(0)) revert InvalidRecipient();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) private {
        if (to == address(0)) revert InvalidRecipient();
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) private {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = fromBalance - value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }

    function _requireExactIncrease(IERC20 token, address account, uint256 beforeBalance, uint256 amount) private view {
        uint256 afterBalance = token.balanceOf(account);
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) {
            revert UnexpectedTokenAmount(address(token));
        }
    }
}
