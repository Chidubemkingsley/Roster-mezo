// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "../src/RosterBtcPutSeries.sol";

interface VmAssetCheck {
    function envAddress(string calldata key) external returns (address value);
}

contract CheckMezoAssets {
    VmAssetCheck private constant vm = VmAssetCheck(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MEZO_TESTNET_CHAIN_ID = 31611;

    error WrongChain(uint256 actualChainId);
    error TokenHasNoCode(address token);
    error WrongDecimals(address token, uint8 actualDecimals);

    event AssetMetadataChecked(address indexed token, uint8 decimals, uint256 totalSupply);

    function run() external {
        if (block.chainid != MEZO_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        address musdAddress = vm.envAddress("MUSD_ADDRESS");
        address btcAddress = vm.envAddress("BTC_ADDRESS");
        _check(musdAddress);
        _check(btcAddress);
    }

    function _check(address token) private {
        if (token.code.length == 0) revert TokenHasNoCode(token);
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        if (tokenDecimals != 18) revert WrongDecimals(token, tokenDecimals);
        uint256 supply = IERC20Metadata(token).totalSupply();
        emit AssetMetadataChecked(token, tokenDecimals, supply);
    }
}
