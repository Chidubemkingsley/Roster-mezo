// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "./RosterBtcPutSeries.sol";

/// @dev Exact-transfer ERC-20 mock for local tests only. Never deploy this as a real asset.
contract MockERC20 is IERC20Metadata {
    string public override name;
    string public override symbol;
    uint8 private immutable _decimals;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error UnauthorizedBurner();
    error BurnAuthorityAlreadySet();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        _decimals = decimals_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 current = allowance[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = current - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @dev The address allowed to emulate Mezo's protocol burn. Set once by the
    ///      trove mock; this keeps the fixture from exposing an unrestricted burn.
    address public burnAuthority;

    function setBurnAuthority(address authority) external {
        if (authority == address(0)) revert ZeroAddress();
        if (burnAuthority != address(0)) revert BurnAuthorityAlreadySet();
        burnAuthority = authority;
    }

    /// @dev Test-only privileged burn used by the Mezo trove mock. Mezo burns MUSD
    ///      directly from the borrower; it does not use an ERC-20 allowance for this.
    function burn(address from, uint256 amount) external {
        if (msg.sender != burnAuthority) revert UnauthorizedBurner();
        _burn(from, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = balance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = balance - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

    /// @dev Adversarial test token that can call back into a target during transferFrom.
    contract CallbackERC20 is MockERC20 {
        address public callbackCaller;
        address public callbackTarget;
        bytes public callbackData;
        bool public callbackEnabled;
        bool public bubbleCallbackFailure;
        bool public lastCallbackSucceeded;
        bytes4 public lastCallbackRevertSelector;

        constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

        function configureCallback(address expectedCaller, address target, bytes calldata data, bool bubbleFailure)
            external
        {
            callbackCaller = expectedCaller;
            callbackTarget = target;
            callbackData = data;
            bubbleCallbackFailure = bubbleFailure;
            callbackEnabled = true;
            lastCallbackSucceeded = false;
            lastCallbackRevertSelector = bytes4(0);
        }

        function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
            super.transferFrom(from, to, amount);
            if (callbackEnabled && msg.sender == callbackCaller) {
                callbackEnabled = false;
                (bool ok, bytes memory result) = callbackTarget.call(callbackData);
                lastCallbackSucceeded = ok;
                if (!ok && result.length >= 4) {
                    bytes4 selector;
                    assembly { selector := mload(add(result, 32)) }
                    lastCallbackRevertSelector = selector;
                }
                if (!ok && bubbleCallbackFailure) {
                    assembly { revert(add(result, 32), mload(result)) }
                }
            }
            return true;
        }
    }

    /// @dev Local adversarial token used to prove exact-transfer checks reject fee-on-transfer assets.
    contract FeeOnTransferERC20 is MockERC20 {
        constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

        function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
            uint256 current = allowance[from][msg.sender];
            if (current != type(uint256).max) {
                if (current < amount) revert InsufficientAllowance();
                unchecked {
                    allowance[from][msg.sender] = current - amount;
                }
                emit Approval(from, msg.sender, allowance[from][msg.sender]);
            }
            uint256 fee = amount / 100; // 1%; rounds down for small amounts, used only in tests
            _transfer(from, to, amount - fee);
            if (fee != 0) {
                uint256 fromBalance = balanceOf[from];
                if (fromBalance < fee) revert InsufficientBalance();
                unchecked {
                    balanceOf[from] = fromBalance - fee;
                    totalSupply -= fee;
                }
                emit Transfer(from, address(0), fee);
            }
            return true;
        }
    }
