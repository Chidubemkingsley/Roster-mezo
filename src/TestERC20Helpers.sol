// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

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
