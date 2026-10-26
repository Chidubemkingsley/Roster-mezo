// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RosterBtcPutSeries, IERC20Metadata} from "../src/RosterBtcPutSeries.sol";

interface VmScript {
    function envAddress(string calldata key) external returns (address value);
    function envUint(string calldata key) external returns (uint256 value);
    function envString(string calldata key) external returns (string memory value);
    function addr(uint256 privateKey) external returns (address keyAddr);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeploySeries {
    VmScript private constant vm = VmScript(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MEZO_TESTNET_CHAIN_ID = 31611;

    error WrongChain(uint256 actualChainId);
    error WriterMustBeDeployer(address writer, address deployer);
    error TokenHasNoCode(address token);
    error WrongTokenDecimals(address token, uint8 actualDecimals);
    error SameTokenAddress();

    event SeriesDeployed(
        address indexed series,
        address indexed writer,
        address musd,
        address btc,
        uint256 strikeRaw,
        uint256 premiumPerLotRaw,
        uint256 expiry
    );

    function run() external returns (RosterBtcPutSeries series) {
        if (block.chainid != MEZO_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        address writer = vm.envAddress("WRITER_ADDRESS");
        if (writer != deployer) revert WriterMustBeDeployer(writer, deployer);

        address musd = vm.envAddress("MUSD_ADDRESS");
        address btc = vm.envAddress("BTC_ADDRESS");
        if (musd == btc) revert SameTokenAddress();
        _checkAsset(musd);
        _checkAsset(btc);
        uint256 strikeRaw = vm.envUint("STRIKE_RAW");
        uint256 premiumPerLotRaw = vm.envUint("PREMIUM_PER_LOT_RAW");
        uint256 expiry = vm.envUint("EXPIRY");
        string memory seriesName = vm.envString("SERIES_NAME");
        string memory seriesSymbol = vm.envString("SERIES_SYMBOL");

        vm.startBroadcast(privateKey);
        series =
            new RosterBtcPutSeries(writer, musd, btc, strikeRaw, premiumPerLotRaw, expiry, seriesName, seriesSymbol);
        vm.stopBroadcast();

        emit SeriesDeployed(address(series), writer, musd, btc, strikeRaw, premiumPerLotRaw, expiry);
    }

    function _checkAsset(address token) private view {
        if (token == address(0) || token.code.length == 0) revert TokenHasNoCode(token);
        uint8 actualDecimals = IERC20Metadata(token).decimals();
        if (actualDecimals != 18) revert WrongTokenDecimals(token, actualDecimals);
        // totalSupply() confirms the configured address exposes the expected ERC-20 metadata surface.
        IERC20Metadata(token).totalSupply();
    }
}
