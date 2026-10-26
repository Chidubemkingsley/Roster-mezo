// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata, RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {RosterOrderBook} from "../src/RosterOrderBook.sol";
import {RosterSeriesFactory} from "../src/RosterSeriesFactory.sol";
import {RosterTroveWriter} from "../src/RosterTroveWriter.sol";

interface VmStack {
    function envAddress(string calldata key) external returns (address value);
    function envUint(string calldata key) external returns (uint256 value);
    function envString(string calldata key) external returns (string memory value);
    function addr(uint256 privateKey) external returns (address keyAddr);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IMezoBorrowerOperationsStack {
    function MUSD_GAS_COMPENSATION() external view returns (uint256);
    function minNetDebt() external view returns (uint256);
    function getBorrowingFee(uint256 debt) external view returns (uint256);
    function borrowingRate() external view returns (uint256);
    function activePool() external view returns (address);
    function collSurplusPool() external view returns (address);
}

interface IMezoTroveManagerStack {
    function getTroveStatus(address borrower) external view returns (uint8);
    function getTroveDebt(address borrower) external view returns (uint256);
    function getTroveColl(address borrower) external view returns (uint256);
    function getCurrentICR(address borrower, uint256 price) external view returns (uint256);
}

interface IMezoPriceFeedStack {
    function fetchPrice() external view returns (uint256);
}

/// @notice Deploys the complete Roster stack and opens the trove-backed writer:
///         factory, secondary ask book, per-series trove vault, factory-created series,
///         series binding, and the initial trove borrow/deposit.
/// @dev Run once without `--broadcast` against a Mezo testnet fork first:
///      forge script script/DeployStack.s.sol:DeployStack --fork-url $MEZO_TESTNET_RPC_URL -vvv
///      Then add `--rpc-url $MEZO_TESTNET_RPC_URL --broadcast` to send the transactions.
contract DeployStack {
    VmStack private constant vm = VmStack(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant MEZO_TESTNET_CHAIN_ID = 31611;
    uint256 private constant WAD = 1e18;
    uint256 private constant MIN_APP_ICR = 1.2e18;
    uint256 private constant MAX_APP_ICR = 5e18;

    error WrongChain(uint256 actualChainId);
    error ZeroAddress(string name);
    error SameTokenAddress();
    error TokenHasNoCode(string name, address token);
    error WrongTokenDecimals(string name, address token, uint8 actualDecimals);
    error ContractHasNoCode(string name, address target);
    error InvalidExpiry(uint256 expiry, uint256 nowTimestamp);
    error InvalidStrike(uint256 strikeRaw);
    error InvalidPremium(uint256 premiumPerLotRaw);
    error InvalidDeposit(uint256 seriesDeposit, uint256 debtAmount);
    error InvalidCollateral(uint256 collateral);
    error InvalidMinICR(uint256 minICR);
    error InsufficientNativeBalance(uint256 balance, uint256 collateral);
    error ProtocolDebtBelowMinimum(uint256 netDebt, uint256 minNetDebt);
    error CurrentICRBelowMinimum(uint256 icr, uint256 minICR);
    error UnexpectedTroveStatus(uint8 status);
    error UnexpectedTroveDebt(uint256 actualDebt, uint256 minimumDebt);
    error UnexpectedSeriesCollateral(uint256 actualCollateral, uint256 expectedCollateral);
    error UnexpectedVaultMUSD(uint256 actualBalance, uint256 expectedBalance);

    event StackDeployed(
        address indexed deployer,
        address indexed factory,
        address indexed orderBook,
        address vault,
        address series,
        uint256 collateral,
        uint256 debt,
        uint256 seriesDeposit,
        uint256 expiry,
        uint256 minICR,
        uint256 borrowingFee,
        uint256 gasCompensation,
        uint256 price,
        uint256 postOpenICR
    );

    function run()
        external
        returns (
            RosterSeriesFactory factory,
            RosterOrderBook orderBook,
            RosterTroveWriter vault,
            RosterBtcPutSeries series
        )
    {
        if (block.chainid != MEZO_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        address musd = vm.envAddress("MUSD_ADDRESS");
        address btc = vm.envAddress("BTC_ADDRESS");
        address borrowerOperations = vm.envAddress("BORROWER_OPERATIONS_ADDRESS");
        address troveManager = vm.envAddress("TROVE_MANAGER_ADDRESS");
        address priceFeed = vm.envAddress("MEZO_PRICE_FEED_ADDRESS");

        uint256 strikeRaw = vm.envUint("STRIKE_RAW");
        uint256 premiumPerLotRaw = vm.envUint("PREMIUM_PER_LOT_RAW");
        uint256 expiry = vm.envUint("EXPIRY");
        string memory seriesName = vm.envString("SERIES_NAME");
        string memory seriesSymbol = vm.envString("SERIES_SYMBOL");

        uint256 collateral = vm.envUint("TROVE_COLLATERAL_RAW");
        uint256 debtAmount = vm.envUint("TROVE_DEBT_RAW");
        uint256 seriesDeposit = vm.envUint("SERIES_DEPOSIT_RAW");
        uint256 minICR = vm.envUint("MIN_ICR_RAW");

        _preflight(
            deployer,
            musd,
            btc,
            borrowerOperations,
            troveManager,
            priceFeed,
            strikeRaw,
            premiumPerLotRaw,
            expiry,
            collateral,
            debtAmount,
            seriesDeposit,
            minICR
        );

        IMezoBorrowerOperationsStack borrowerOps = IMezoBorrowerOperationsStack(borrowerOperations);
        IMezoTroveManagerStack troveMgr = IMezoTroveManagerStack(troveManager);
        IMezoPriceFeedStack feed = IMezoPriceFeedStack(priceFeed);

        uint256 borrowingFee = borrowerOps.getBorrowingFee(debtAmount);
        uint256 gasCompensation = borrowerOps.MUSD_GAS_COMPENSATION();
        uint256 price = feed.fetchPrice();
        uint256 expectedDebt = debtAmount + borrowingFee + gasCompensation;

        vm.startBroadcast(privateKey);

        factory = new RosterSeriesFactory(musd, btc);
        orderBook = new RosterOrderBook(musd, address(factory));
        vault = new RosterTroveWriter(deployer, borrowerOperations, troveManager, priceFeed, musd, btc, minICR);
        series = factory.createSeries(address(vault), strikeRaw, premiumPerLotRaw, expiry, seriesName, seriesSymbol);
        vault.bindSeries(address(series));
        vault.openAndFund{value: collateral}(debtAmount, seriesDeposit, address(0), address(0));

        vm.stopBroadcast();

        uint8 status = troveMgr.getTroveStatus(address(vault));
        if (status != 1) revert UnexpectedTroveStatus(status);

        uint256 actualDebt = troveMgr.getTroveDebt(address(vault));
        if (actualDebt < expectedDebt) revert UnexpectedTroveDebt(actualDebt, expectedDebt);

        uint256 actualSeriesCollateral = series.collateral_balance_raw();
        if (actualSeriesCollateral != seriesDeposit) {
            revert UnexpectedSeriesCollateral(actualSeriesCollateral, seriesDeposit);
        }

        uint256 expectedVaultMUSD = debtAmount - seriesDeposit;
        uint256 actualVaultMUSD = IERC20Metadata(musd).balanceOf(address(vault));
        if (actualVaultMUSD != expectedVaultMUSD) {
            revert UnexpectedVaultMUSD(actualVaultMUSD, expectedVaultMUSD);
        }

        uint256 postOpenICR = troveMgr.getCurrentICR(address(vault), price);
        emit StackDeployed(
            deployer,
            address(factory),
            address(orderBook),
            address(vault),
            address(series),
            collateral,
            actualDebt,
            seriesDeposit,
            expiry,
            minICR,
            borrowingFee,
            gasCompensation,
            price,
            postOpenICR
        );
    }

    function _preflight(
        address deployer,
        address musd,
        address btc,
        address borrowerOperations,
        address troveManager,
        address priceFeed,
        uint256 strikeRaw,
        uint256 premiumPerLotRaw,
        uint256 expiry,
        uint256 collateral,
        uint256 debtAmount,
        uint256 seriesDeposit,
        uint256 minICR
    ) private view {
        if (musd == address(0)) revert ZeroAddress("MUSD_ADDRESS");
        if (btc == address(0)) revert ZeroAddress("BTC_ADDRESS");
        if (musd == btc) revert SameTokenAddress();
        _checkAsset("MUSD_ADDRESS", musd);
        _checkAsset("BTC_ADDRESS", btc);

        _checkContract("BORROWER_OPERATIONS_ADDRESS", borrowerOperations);
        _checkContract("TROVE_MANAGER_ADDRESS", troveManager);
        _checkContract("MEZO_PRICE_FEED_ADDRESS", priceFeed);

        if (expiry <= block.timestamp) revert InvalidExpiry(expiry, block.timestamp);
        if (strikeRaw == 0 || strikeRaw % 1e6 != 0 || strikeRaw / 1e6 == 0) {
            revert InvalidStrike(strikeRaw);
        }
        if (premiumPerLotRaw == 0) revert InvalidPremium(premiumPerLotRaw);
        if (seriesDeposit == 0 || seriesDeposit > debtAmount) {
            revert InvalidDeposit(seriesDeposit, debtAmount);
        }
        if (collateral == 0) revert InvalidCollateral(collateral);
        if (minICR < MIN_APP_ICR || minICR > MAX_APP_ICR) revert InvalidMinICR(minICR);

        if (deployer.balance <= collateral) revert InsufficientNativeBalance(deployer.balance, collateral);

        IMezoBorrowerOperationsStack borrowerOps = IMezoBorrowerOperationsStack(borrowerOperations);
        uint256 borrowingFee = borrowerOps.getBorrowingFee(debtAmount);
        uint256 gasCompensation = borrowerOps.MUSD_GAS_COMPENSATION();
        uint256 netDebt = debtAmount + borrowingFee;
        uint256 minNetDebt = borrowerOps.minNetDebt();
        if (netDebt < minNetDebt) revert ProtocolDebtBelowMinimum(netDebt, minNetDebt);

        uint256 price = IMezoPriceFeedStack(priceFeed).fetchPrice();
        uint256 compositeDebt = netDebt + gasCompensation;
        uint256 icr = (collateral * price) / compositeDebt;
        if (icr < minICR) revert CurrentICRBelowMinimum(icr, minICR);

        address activePool = borrowerOps.activePool();
        address collSurplusPool = borrowerOps.collSurplusPool();
        _checkContract("ACTIVE_POOL", activePool);
        _checkContract("COLL_SURPLUS_POOL", collSurplusPool);
    }

    function _checkAsset(string memory name, address token) private view {
        if (token.code.length == 0) revert TokenHasNoCode(name, token);
        uint8 actualDecimals = IERC20Metadata(token).decimals();
        if (actualDecimals != 18) revert WrongTokenDecimals(name, token, actualDecimals);
        IERC20Metadata(token).totalSupply();
    }

    function _checkContract(string memory name, address target) private view {
        if (target == address(0)) revert ZeroAddress(name);
        if (target.code.length == 0) revert ContractHasNoCode(name, target);
    }
}
