// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase, Vm} from "./TestBase.sol";
import {RosterBtcPutSeries} from "../src/RosterBtcPutSeries.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {RosterSeriesFactory} from "../src/RosterSeriesFactory.sol";
import {RosterOrderBook} from "../src/RosterOrderBook.sol";
import {RosterTroveWriter} from "../src/RosterTroveWriter.sol";

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

contract RosterSeriesFactoryTest is TestBase {
    RosterSeriesFactory internal factory;

    function setUp() public override {
        super.setUp();
        factory = new RosterSeriesFactory(address(musd), address(btc));
    }

    function test_factory_creates_registers_and_exposes_terms() public {
        RosterBtcPutSeries created =
            factory.createSeries(writer, K_RAW, PREMIUM_PER_LOT, expiryTime, "Factory Put", "FPUT");

        _assertEq(factory.seriesCount(), 1, "series count");
        _assertEq(factory.seriesAt(0), address(created), "series at zero");
        _assertTrue(factory.isSeries(address(created)), "series registered");
        _assertEq(created.writer(), writer, "writer");
        _assertEq(address(created.musd()), address(musd), "musd");
        _assertEq(address(created.btc()), address(btc), "btc");
        _assertEq(created.K_raw(), K_RAW, "strike");
        _assertEq(created.premium_per_lot_raw(), PREMIUM_PER_LOT, "premium");
        _assertEq(created.expiry(), expiryTime, "expiry");
        _assertEq(created.name(), "Factory Put", "name");
        _assertEq(created.symbol(), "FPUT", "symbol");
    }

    function test_factory_allows_multiple_writers_and_series() public {
        RosterBtcPutSeries first = factory.createSeries(writer, K_RAW, PREMIUM_PER_LOT, expiryTime, "Writer A", "WA");
        RosterBtcPutSeries second =
            factory.createSeries(alice, 70_000 * 1e18, 2e15, expiryTime + 30 days, "Writer B", "WB");

        _assertEq(factory.seriesCount(), 2, "two series");
        _assertEq(factory.seriesAt(0), address(first), "first series");
        _assertEq(factory.seriesAt(1), address(second), "second series");
        _assertEq(second.writer(), alice, "second writer");
        _assertTrue(factory.isSeries(address(first)), "first known");
        _assertTrue(factory.isSeries(address(second)), "second known");
    }

    function test_factory_rejects_invalid_constructor_parameters() public {
        vm.expectRevert(RosterSeriesFactory.ZeroAddress.selector);
        factory.createSeries(address(0), K_RAW, PREMIUM_PER_LOT, expiryTime, "X", "X");

        vm.expectRevert(RosterBtcPutSeries.InvalidPremium.selector);
        factory.createSeries(writer, K_RAW, 0, expiryTime, "X", "X");

        vm.expectRevert(RosterBtcPutSeries.InvalidExpiry.selector);
        factory.createSeries(writer, K_RAW, PREMIUM_PER_LOT, block.timestamp, "X", "X");
    }

    function test_factory_rejects_bad_asset_pair() public {
        vm.expectRevert(RosterSeriesFactory.IdenticalTokenAddresses.selector);
        new RosterSeriesFactory(address(musd), address(musd));
    }
}

// ---------------------------------------------------------------------------
// Secondary ask book
// ---------------------------------------------------------------------------

contract RosterOrderBookTest is TestBase {
    RosterSeriesFactory internal factory;
    RosterOrderBook internal book;

    function setUp() public override {
        super.setUp();

        // The book only accepts factory-created series, so replace the direct fixture
        // series with one produced by the registry and re-approve the new series.
        factory = new RosterSeriesFactory(address(musd), address(btc));
        series = factory.createSeries(writer, K_RAW, PREMIUM_PER_LOT, expiryTime, "Book Put", "BPUT");
        book = new RosterOrderBook(address(musd), address(factory));

        vm.prank(writer);
        musd.approve(address(series), type(uint256).max);
        vm.prank(alice);
        musd.approve(address(series), type(uint256).max);
        vm.prank(bob);
        musd.approve(address(series), type(uint256).max);
        vm.prank(carol);
        musd.approve(address(series), type(uint256).max);

        _deposit(10 * STRIKE_PER_LOT);
        _buy(alice, 10);

        vm.prank(alice);
        series.approve(address(book), type(uint256).max);
        vm.prank(bob);
        musd.approve(address(book), type(uint256).max);
        vm.prank(carol);
        musd.approve(address(book), type(uint256).max);
    }

    function test_order_book_rejects_unregistered_series() public {
        RosterBtcPutSeries unregistered = new RosterBtcPutSeries(
            writer, address(musd), address(btc), K_RAW, PREMIUM_PER_LOT, expiryTime, "Unregistered", "UNREG"
        );

        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.SeriesNotRegistered.selector);
        book.list(address(unregistered), 1, 1e15);
    }

    function test_order_book_rejects_mismatched_musd_series() public {
        MockERC20 otherMusd = new MockERC20("Other USD", "OUSD", 18);
        RosterSeriesFactory otherFactory = new RosterSeriesFactory(address(otherMusd), address(btc));
        RosterBtcPutSeries otherSeries =
            otherFactory.createSeries(writer, K_RAW, PREMIUM_PER_LOT, expiryTime, "Other Put", "OPUT");

        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.SeriesMismatchedMUSD.selector);
        book.list(address(otherSeries), 1, 1e15);
    }

    function test_order_book_constructor_rejects_factory_with_different_musd() public {
        MockERC20 otherMusd = new MockERC20("Other USD", "OUSD", 18);
        RosterSeriesFactory otherFactory = new RosterSeriesFactory(address(otherMusd), address(btc));

        vm.expectRevert(RosterOrderBook.InvalidFactory.selector);
        new RosterOrderBook(address(musd), address(otherFactory));
    }

    function test_list_and_partial_fill_moves_tokens_and_musd() public {
        vm.prank(alice);
        uint256 listingId = book.list(address(series), 10, 2e15);

        _assertEq(listingId, 1, "listing id");
        _assertEq(series.balanceOf(alice), 0, "alice escrowed");
        _assertEq(series.balanceOf(address(book)), 10, "book escrow");
        (address seller, RosterBtcPutSeries listedSeries, uint256 pricePerLot, uint256 remaining, bool active) =
            book.listings(listingId);
        _assertEq(seller, alice, "seller");
        _assertEq(address(listedSeries), address(series), "series");
        _assertEq(pricePerLot, 2e15, "price");
        _assertEq(remaining, 10, "remaining");
        _assertTrue(active, "active");

        uint256 aliceBefore = musd.balanceOf(alice);
        uint256 bobBefore = musd.balanceOf(bob);
        vm.prank(bob);
        book.fill(listingId, 4);

        _assertEq(series.balanceOf(bob), 4, "bob lots");
        _assertEq(series.balanceOf(address(book)), 6, "remaining escrow");
        _assertEq(musd.balanceOf(alice) - aliceBefore, 8e15, "seller paid");
        _assertEq(bobBefore - musd.balanceOf(bob), 8e15, "buyer charged");
        (,,, remaining, active) = book.listings(listingId);
        _assertEq(remaining, 6, "remaining after fill");
        _assertTrue(active, "still active");
    }

    function test_partial_fill_then_cancel_returns_remainder() public {
        vm.prank(alice);
        uint256 listingId = book.list(address(series), 10, 2e15);
        vm.prank(bob);
        book.fill(listingId, 4);
        vm.prank(alice);
        book.cancel(listingId);

        _assertEq(series.balanceOf(alice), 6, "alice remainder");
        _assertEq(series.balanceOf(bob), 4, "bob bought");
        _assertEq(series.balanceOf(address(book)), 0, "book empty");
        (,,, uint256 remaining, bool active) = book.listings(listingId);
        _assertEq(remaining, 0, "no remaining");
        _assertTrue(!active, "inactive");
    }

    function test_full_fill_deactivates_listing() public {
        vm.prank(alice);
        book.list(address(series), 3, 1e15);
        vm.prank(bob);
        book.fill(1, 3);
        (,,, uint256 remaining, bool active) = book.listings(1);
        _assertEq(remaining, 0, "remaining zero");
        _assertTrue(!active, "inactive");
        _assertEq(series.balanceOf(bob), 3, "bob lots");
    }

    function test_cancel_only_seller() public {
        vm.prank(alice);
        book.list(address(series), 2, 1e15);
        vm.expectRevert(RosterOrderBook.NotSeller.selector);
        vm.prank(bob);
        book.cancel(1);
    }

    function test_list_requires_position_approval() public {
        vm.prank(bob);
        vm.expectRevert(RosterBtcPutSeries.InsufficientAllowance.selector);
        book.list(address(series), 1, 1e15);
    }

    function test_fill_requires_musd_allowance() public {
        vm.prank(alice);
        book.list(address(series), 1, 1e15);
        vm.prank(attacker);
        vm.expectRevert(MockERC20.InsufficientAllowance.selector);
        book.fill(1, 1);
    }

    function test_list_after_maturity_reverts() public {
        vm.warp(expiryTime);
        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.SeriesNotLive.selector);
        book.list(address(series), 1, 1e15);
    }

    function test_fill_and_cancel_after_maturity_revert() public {
        vm.prank(alice);
        book.list(address(series), 2, 1e15);
        vm.warp(expiryTime);

        vm.prank(bob);
        vm.expectRevert(RosterOrderBook.SeriesNotLive.selector);
        book.fill(1, 1);

        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.SeriesNotLive.selector);
        book.cancel(1);
    }

    function test_unknown_and_overfilled_listings_revert() public {
        vm.expectRevert(RosterOrderBook.UnknownListing.selector);
        vm.prank(bob);
        book.fill(99, 1);

        vm.prank(alice);
        book.list(address(series), 2, 1e15);
        vm.prank(bob);
        vm.expectRevert(RosterOrderBook.InsufficientListing.selector);
        book.fill(1, 3);
    }

    function test_invalid_listing_inputs_revert() public {
        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.InvalidQuantity.selector);
        book.list(address(series), 0, 1e15);

        vm.prank(alice);
        vm.expectRevert(RosterOrderBook.InvalidPrice.selector);
        book.list(address(series), 1, 0);

        vm.expectRevert(RosterOrderBook.InvalidQuantity.selector);
        vm.prank(bob);
        book.fill(1, 0);
    }
}

// ---------------------------------------------------------------------------
// Trove-backed writer
// ---------------------------------------------------------------------------

contract MockPriceFeed {
    uint256 public price;

    constructor(uint256 price_) {
        price = price_;
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function fetchPrice() external view returns (uint256) {
        return price;
    }
}

contract MockPool {
    receive() external payable {}

    function send(address payable to, uint256 amount) external {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "mock pool send failed");
    }
}

contract MockTroveSystem {
    uint256 public constant MUSD_GAS_COMPENSATION = 200e18;
    uint256 public constant BORROWING_FEE_BPS = 10; // Mezo testnet: 0.1%

    MockERC20 public immutable musd;
    address public immutable activePool;
    address public immutable collSurplusPool;
    address public constant FEE_RECIPIENT = address(0xFEE);

    mapping(address => uint8) public status;
    mapping(address => uint256) public coll;
    mapping(address => uint256) public debt;
    mapping(address => uint256) public pendingInterest;
    uint256 public collateralSurplus;

    constructor(MockERC20 musd_, address activePool_, address collSurplusPool_) {
        musd = musd_;
        activePool = activePool_;
        collSurplusPool = collSurplusPool_;
        musd_.setBurnAuthority(address(this));
    }

    receive() external payable {}

    function setCollateralSurplus(uint256 amount) external {
        collateralSurplus = amount;
    }

    /// @dev Test hook that models interest accruing between trove actions.
    function accrueInterest(address borrower, uint256 amount) external {
        pendingInterest[borrower] += amount;
    }

    /// @dev Mirrors BorrowerOperations/TroveManager: interest must be folded into the
    ///      stored debt before a repayment or closure reads the outstanding amount.
    function updateSystemAndTroveInterest(address borrower) public {
        uint256 interest = pendingInterest[borrower];
        if (interest != 0) {
            pendingInterest[borrower] = 0;
            debt[borrower] += interest;
        }
    }

    function openTrove(uint256 debtAmount, address, address) external payable {
        require(status[msg.sender] != 1, "mock: trove active");
        status[msg.sender] = 1;
        coll[msg.sender] = msg.value;
        uint256 fee = (debtAmount * BORROWING_FEE_BPS) / 10_000;
        debt[msg.sender] = debtAmount + fee + MUSD_GAS_COMPENSATION;
        musd.mint(msg.sender, debtAmount);
        musd.mint(FEE_RECIPIENT, fee);
        (bool ok,) = activePool.call{value: msg.value}("");
        require(ok, "mock: open collateral transfer");
    }

    function addColl(address, address) external payable {
        require(status[msg.sender] == 1, "mock: no trove");
        coll[msg.sender] += msg.value;
        (bool ok,) = activePool.call{value: msg.value}("");
        require(ok, "mock: add collateral transfer");
    }

    function withdrawColl(uint256 amount, address, address) external {
        require(status[msg.sender] == 1, "mock: no trove");
        require(coll[msg.sender] >= amount, "mock: collateral");
        coll[msg.sender] -= amount;
        MockPool(payable(activePool)).send(payable(msg.sender), amount);
    }

    function withdrawMUSD(uint256 amount, address, address) external {
        require(status[msg.sender] == 1, "mock: no trove");
        uint256 fee = (amount * BORROWING_FEE_BPS) / 10_000;
        debt[msg.sender] += amount + fee;
        musd.mint(msg.sender, amount);
        musd.mint(FEE_RECIPIENT, fee);
    }

    function repayMUSD(uint256 amount, address, address) external {
        require(status[msg.sender] == 1, "mock: no trove");
        updateSystemAndTroveInterest(msg.sender);
        require(debt[msg.sender] >= amount, "mock: debt");
        debt[msg.sender] -= amount;
        // Mezo burns directly from the borrower; no ERC-20 allowance is involved.
        musd.burn(msg.sender, amount);
    }

    function closeTrove() external {
        require(status[msg.sender] == 1, "mock: no trove");
        updateSystemAndTroveInterest(msg.sender);
        uint256 debtAmount = debt[msg.sender];
        uint256 collateralAmount = coll[msg.sender];
        uint256 repayment = debtAmount - MUSD_GAS_COMPENSATION;
        require(musd.balanceOf(msg.sender) >= repayment, "mock: insufficient musd");
        musd.burn(msg.sender, repayment);
        status[msg.sender] = 2;
        coll[msg.sender] = 0;
        debt[msg.sender] = 0;
        MockPool(payable(activePool)).send(payable(msg.sender), collateralAmount);
    }

    function claimCollateral() external {
        uint256 amount = collateralSurplus;
        require(amount != 0, "mock: no surplus");
        collateralSurplus = 0;
        MockPool(payable(collSurplusPool)).send(payable(msg.sender), amount);
    }

    function getTroveStatus(address borrower) external view returns (uint8) {
        return status[borrower];
    }

    function getTroveDebt(address borrower) external view returns (uint256) {
        return debt[borrower] + pendingInterest[borrower];
    }

    function getTroveColl(address borrower) external view returns (uint256) {
        return coll[borrower];
    }

    function getCurrentICR(address borrower, uint256 price) external view returns (uint256) {
        uint256 totalDebt = debt[borrower] + pendingInterest[borrower];
        if (totalDebt == 0) return type(uint256).max;
        return (coll[borrower] * price) / totalDebt;
    }
}

contract RosterTroveWriterTest is TestBase {
    RosterSeriesFactory internal factory;
    MockTroveSystem internal troveSystem;
    MockPriceFeed internal priceFeed;
    MockPool internal activePool;
    MockPool internal collSurplusPool;
    RosterTroveWriter internal vault;
    RosterBtcPutSeries internal vaultSeries;

    function setUp() public override {
        super.setUp();
        activePool = new MockPool();
        collSurplusPool = new MockPool();
        priceFeed = new MockPriceFeed(80_000e18);
        troveSystem = new MockTroveSystem(musd, address(activePool), address(collSurplusPool));
        vault = new RosterTroveWriter(
            writer, address(troveSystem), address(troveSystem), address(priceFeed), address(musd), address(btc), 1.5e18
        );

        factory = new RosterSeriesFactory(address(musd), address(btc));
        vaultSeries = factory.createSeries(address(vault), K_RAW, PREMIUM_PER_LOT, expiryTime, "Trove Put", "TPUT");

        vm.prank(writer);
        vault.bindSeries(address(vaultSeries));
        vm.deal(writer, 10 ether);
    }

    function _open(uint256 collateral, uint256 debtAmount, uint256 seriesDeposit) internal {
        vm.prank(writer);
        vault.openAndFund{value: collateral}(debtAmount, seriesDeposit, address(0), address(0));
    }

    function _enableAlice() internal {
        vm.prank(alice);
        musd.approve(address(vaultSeries), type(uint256).max);
    }

    function test_open_and_fund_creates_separate_series_and_trove() public {
        _open(1 ether, 2_000e18, 1_500e18);

        _assertEq(vaultSeries.writer(), address(vault), "vault is writer");
        _assertEq(vaultSeries.collateral_balance_raw(), 1_500e18, "series collateral");
        _assertEq(vaultSeries.premium_balance_raw(), 0, "no premium");
        _assertEq(troveSystem.debt(address(vault)), 2_202e18, "trove debt incl fee and gas");
        _assertEq(troveSystem.coll(address(vault)), 1 ether, "trove collateral");
        _assertTrue(vault.isTroveActive(), "active trove");
        _assertEq(vault.totalDepositedToSeries(), 1_500e18, "tracked deposit");
        _assertEq(musd.balanceOf(address(vault)), 500e18, "idle borrowed musd");
    }

    function test_trove_info_and_series_state() public {
        _open(1 ether, 2_000e18, 1_500e18);
        (uint256 collateral, uint256 debt, uint256 icr, uint256 price, uint8 status) = vault.troveInfo();
        _assertEq(collateral, 1 ether, "info collateral");
        _assertEq(debt, 2_202e18, "info debt");
        _assertTrue(icr >= 1.5e18, "icr above guardrail");
        _assertEq(price, 80_000e18, "price");
        _assertEq(status, 1, "status active");

        (uint256 seriesCollateral, uint256 seriesPremium, uint256 activeLots, bool expired) = vault.seriesState();
        _assertEq(seriesCollateral, 1_500e18, "series collateral");
        _assertEq(seriesPremium, 0, "series premium");
        _assertEq(activeLots, 0, "active lots");
        _assertTrue(!expired, "not expired");
    }

    function test_open_and_fund_only_owner() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(RosterTroveWriter.OnlyOwner.selector);
        vault.openAndFund{value: 1 ether}(2_000e18, 1_500e18, address(0), address(0));
    }

    function test_open_twice_reverts() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.TroveAlreadyOpen.selector);
        vault.openAndFund{value: 1 ether}(2_000e18, 1_500e18, address(0), address(0));
    }

    function test_open_rejects_bad_deposit_and_zero_collateral() public {
        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.NoCollateral.selector);
        vault.openAndFund{value: 0}(2_000e18, 1_500e18, address(0), address(0));

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.InvalidDeposit.selector);
        vault.openAndFund{value: 1 ether}(2_000e18, 0, address(0), address(0));

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.InvalidDeposit.selector);
        vault.openAndFund{value: 1 ether}(1_000e18, 1_500e18, address(0), address(0));
    }

    function test_icr_guard_reverts_unsafe_open_atomically() public {
        vm.prank(writer);
        vm.expectRevert();
        vault.openAndFund{value: 0.01 ether}(2_000e18, 1_500e18, address(0), address(0));

        _assertEq(troveSystem.getTroveStatus(address(vault)), 0, "trove rolled back");
        _assertEq(vaultSeries.collateral_balance_raw(), 0, "series rolled back");
        _assertEq(musd.balanceOf(address(vault)), 0, "musd rolled back");
    }

    function test_add_and_withdraw_collateral() public {
        _open(1 ether, 2_000e18, 1_500e18);

        vm.prank(writer);
        vault.addCollateral{value: 0.5 ether}(address(0), address(0));
        _assertEq(troveSystem.coll(address(vault)), 1.5 ether, "added collateral");
        uint256 beforeWithdraw = writer.balance;

        vm.prank(writer);
        vault.withdrawCollateral(0.2 ether, address(0), address(0));
        _assertEq(troveSystem.coll(address(vault)), 1.3 ether, "withdrawn collateral");
        _assertEq(writer.balance - beforeWithdraw, 0.2 ether, "native returned");
    }

    function test_borrow_more_and_deposit_to_series() public {
        _open(1 ether, 2_000e18, 1_500e18);

        vm.prank(writer);
        vault.borrowMore(100e18, address(0), address(0));
        _assertEq(troveSystem.debt(address(vault)), 2_302e18 + 1e17, "debt increased with fee");
        _assertEq(musd.balanceOf(address(vault)), 600e18, "idle musd increased");

        vm.prank(writer);
        vault.depositToSeries(50e18);
        _assertEq(vaultSeries.collateral_balance_raw(), 1_550e18, "series funded");
        _assertEq(musd.balanceOf(address(vault)), 550e18, "idle reduced");
    }

    function test_borrow_more_icr_guard() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(writer);
        vault.setMinICR(5e18);

        vm.prank(writer);
        vm.expectRevert();
        vault.borrowMore(60_000e18, address(0), address(0));
        _assertEq(troveSystem.debt(address(vault)), 2_202e18, "debt rolled back");
    }

    function test_partial_repay() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(writer);
        vault.withdrawIdleMUSD(200e18);
        vm.prank(writer);
        musd.approve(address(vault), 100e18);

        vm.prank(writer);
        vault.repay(100e18, address(0), address(0));
        _assertEq(troveSystem.debt(address(vault)), 2_102e18, "debt reduced");
    }

    function test_close_trove_repays_only_debt_minus_gas_compensation() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(writer);
        vault.withdrawIdleMUSD(500e18);
        vm.prank(writer);
        musd.approve(address(vault), 2_002e18);
        uint256 writerBefore = writer.balance;

        vm.prank(writer);
        vault.closeTrove();

        _assertEq(troveSystem.getTroveStatus(address(vault)), 2, "closed by owner");
        _assertTrue(!vault.isTroveActive(), "not active");
        _assertEq(writer.balance - writerBefore, 1 ether, "collateral returned");
        _assertEq(musd.balanceOf(address(vault)), 0, "no unnecessary gas compensation retained");
        _assertEq(musd.allowance(address(vault), address(troveSystem)), 0, "no protocol allowance");
    }

    function test_close_trove_requires_external_musd_for_borrowing_fee() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.warp(expiryTime);
        vm.prank(alice);
        vaultSeries.expire();

        // The vault owns 2,000 MUSD (500 idle + 1,500 released), but Mezo debt is
        // 2,202 MUSD and closeTrove needs debt minus the 200 MUSD gas compensation.
        _assertEq(musd.balanceOf(address(vault)), 2_000e18, "vault own funds");
        _assertEq(vault.reservedMUSD(), 1_500e18, "release reserved");

        vm.prank(writer);
        vm.expectRevert(MockERC20.InsufficientAllowance.selector);
        vault.closeTrove();

        // The owner must gross-fund 1,502 MUSD because the 1,500 reserved for the
        // series cannot be spent. Finalization then returns the 1,500; the net cost
        // to the owner is the 2 MUSD borrowing fee.
        uint256 writerBefore = musd.balanceOf(writer);
        vm.prank(writer);
        musd.approve(address(vault), 1_502e18);
        vm.prank(writer);
        vault.closeTrove();

        _assertEq(troveSystem.getTroveStatus(address(vault)), 2, "trove closed");
        _assertEq(musd.balanceOf(address(vault)), 1_500e18, "reserve preserved");

        vm.prank(writer);
        (uint256 released,) = vault.finalize();
        _assertEq(released, 1_500e18, "reserve forwarded");
        _assertEq(writerBefore - musd.balanceOf(writer), 2e18, "net borrowing fee");
    }

    function test_close_trove_updates_interest_before_top_up() public {
        _open(1 ether, 2_000e18, 1_500e18);
        troveSystem.accrueInterest(address(vault), 10e18);
        vm.prank(writer);
        vault.withdrawIdleMUSD(500e18);
        vm.prank(writer);
        musd.approve(address(vault), type(uint256).max);

        vm.prank(writer);
        vault.closeTrove();

        _assertEq(troveSystem.getTroveStatus(address(vault)), 2, "closed after interest");
        _assertEq(musd.balanceOf(address(vault)), 0, "interest fully repaid");
    }

    function test_close_trove_requires_musd_and_active_trove() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(writer);
        vault.withdrawIdleMUSD(500e18);

        vm.prank(writer);
        vm.expectRevert(MockERC20.InsufficientAllowance.selector);
        vault.closeTrove();
        _assertTrue(vault.isTroveActive(), "still active after failed close");

        vm.prank(writer);
        musd.approve(address(vault), 2_002e18);
        vm.prank(writer);
        vault.closeTrove();

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(RosterTroveWriter.TroveNotActive.selector, 2));
        vault.closeTrove();
    }

    function test_add_and_borrow_require_active_trove() public {
        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(RosterTroveWriter.TroveNotActive.selector, 0));
        vault.addCollateral{value: 1 ether}(address(0), address(0));

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(RosterTroveWriter.TroveNotActive.selector, 0));
        vault.borrowMore(1e18, address(0), address(0));
    }

    function test_claim_collateral_surplus_from_pool() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.deal(address(collSurplusPool), 1 ether);
        troveSystem.setCollateralSurplus(0.1 ether);
        uint256 writerBefore = writer.balance;

        vm.prank(writer);
        uint256 received = vault.claimCollateral();
        _assertEq(received, 0.1 ether, "surplus received");
        _assertEq(writer.balance - writerBefore, 0.1 ether, "surplus forwarded");
    }

    function test_receive_rejects_unexpected_native_sender() public {
        vm.deal(attacker, 1);
        vm.prank(attacker);
        (bool ok,) = address(vault).call{value: 1}("");
        _assertTrue(!ok, "stranger native rejected");
    }

    function test_withdraw_premium_and_finalize() public {
        _open(1 ether, 2_000e18, 1_500e18);
        _enableAlice();
        vm.prank(alice);
        vaultSeries.purchase(10);

        uint256 writerBefore = musd.balanceOf(writer);
        vm.prank(writer);
        uint256 premium = vault.withdrawPremium();
        _assertEq(premium, 10 * PREMIUM_PER_LOT, "premium withdrawn");
        _assertEq(musd.balanceOf(writer) - writerBefore, 10 * PREMIUM_PER_LOT, "premium forwarded");

        vm.warp(expiryTime);
        uint256 beforeFinalize = musd.balanceOf(writer);
        vm.prank(writer);
        (uint256 released, uint256 finalPremium) = vault.finalize();
        _assertEq(released, 1_500e18, "excess collateral released");
        _assertEq(finalPremium, 0, "premium already withdrawn");
        _assertEq(musd.balanceOf(writer) - beforeFinalize, 1_500e18, "collateral forwarded");
        _assertTrue(vaultSeries.expired(), "series expired");
        _assertEq(musd.balanceOf(address(vault)), 500e18, "idle borrow remains");
    }

    function test_withdraw_btc_exercise_proceeds() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.prank(alice);
        musd.approve(address(vaultSeries), type(uint256).max);
        vm.prank(alice);
        btc.approve(address(vaultSeries), type(uint256).max);
        vm.prank(alice);
        vaultSeries.purchase(100);
        vm.prank(alice);
        vaultSeries.exercise(100);

        uint256 exerciseBtc = 100 * 1e12;
        _assertEq(btc.balanceOf(address(vault)), exerciseBtc, "vault holds exercise proceeds");

        vm.prank(alice);
        vm.expectRevert(RosterTroveWriter.OnlyOwner.selector);
        vault.withdrawBtc(alice, exerciseBtc);

        uint256 writerBefore = btc.balanceOf(writer);
        vm.prank(writer);
        vault.withdrawBtc(writer, exerciseBtc);
        _assertEq(btc.balanceOf(writer) - writerBefore, exerciseBtc, "btc forwarded");
        _assertEq(btc.balanceOf(address(vault)), 0, "vault btc cleared");
    }

    function test_third_party_expire_then_finalize_forwards_once() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.warp(expiryTime);

        // Anyone may finalize the series; the released MUSD lands in the vault.
        vm.prank(alice);
        vaultSeries.expire();
        _assertEq(musd.balanceOf(address(vault)), 2_000e18, "idle plus released");
        _assertEq(vault.reservedMUSD(), 1_500e18, "release reserved");

        vm.prank(writer);
        vm.expectRevert(abi.encodeWithSelector(RosterTroveWriter.InsufficientIdleMUSD.selector, 1_600e18, 500e18));
        vault.withdrawIdleMUSD(1_600e18);

        vm.prank(writer);
        vault.withdrawIdleMUSD(500e18);
        _assertEq(musd.balanceOf(address(vault)), 1_500e18, "only idle withdrawn");

        uint256 writerBefore = musd.balanceOf(writer);
        vm.prank(writer);
        (uint256 released,) = vault.finalize();
        _assertEq(released, 1_500e18, "release forwarded once");
        _assertEq(musd.balanceOf(writer) - writerBefore, 1_500e18, "writer received release");
        _assertEq(vault.reservedMUSD(), 0, "reserve cleared");

        vm.prank(writer);
        (uint256 secondRelease, uint256 secondPremium) = vault.finalize();
        _assertEq(secondRelease, 0, "no second release");
        _assertEq(secondPremium, 0, "no second premium");
    }

    function test_close_trove_preserves_reserved_expiry_proceeds() public {
        _open(1 ether, 2_000e18, 1_500e18);
        vm.warp(expiryTime);
        vm.prank(alice);
        vaultSeries.expire();
        _assertEq(vault.reservedMUSD(), 1_500e18, "release reserved");

        vm.prank(writer);
        musd.approve(address(vault), 2_002e18);
        vm.prank(writer);
        vault.closeTrove();

        _assertEq(troveSystem.getTroveStatus(address(vault)), 2, "trove closed");
        _assertEq(musd.balanceOf(address(vault)), 1_500e18, "reserved proceeds preserved");
        _assertEq(vault.reservedMUSD(), 1_500e18, "still reserved");

        uint256 writerBefore = musd.balanceOf(writer);
        vm.prank(writer);
        vault.finalize();
        _assertEq(musd.balanceOf(writer) - writerBefore, 1_500e18, "release forwarded");
    }

    function test_open_requires_bound_series_and_bind_validation() public {
        RosterTroveWriter unbound = new RosterTroveWriter(
            writer, address(troveSystem), address(troveSystem), address(priceFeed), address(musd), address(btc), 1.5e18
        );

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.SeriesNotBound.selector);
        unbound.openAndFund{value: 1 ether}(2_000e18, 1_500e18, address(0), address(0));

        // A series whose writer is not this vault cannot be bound.
        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.InvalidSeries.selector);
        unbound.bindSeries(address(series));

        RosterBtcPutSeries matching =
            factory.createSeries(address(unbound), K_RAW, PREMIUM_PER_LOT, expiryTime, "Unbound Put", "UPUT");
        vm.prank(writer);
        unbound.bindSeries(address(matching));
        _assertEq(address(unbound.series()), address(matching), "bound matching series");

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.SeriesAlreadyBound.selector);
        unbound.bindSeries(address(matching));
    }

    function test_set_min_icr_and_ownership() public {
        vm.prank(writer);
        vault.setMinICR(1.6e18);
        _assertEq(vault.minICR(), 1.6e18, "min icr updated");

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.InvalidMinICR.selector);
        vault.setMinICR(1.0e18);

        vm.prank(alice);
        vm.expectRevert(RosterTroveWriter.OnlyOwner.selector);
        vault.setMinICR(1.6e18);

        vm.prank(writer);
        vault.transferOwnership(alice);
        _assertEq(vault.owner(), alice, "ownership transferred");

        vm.prank(writer);
        vm.expectRevert(RosterTroveWriter.OnlyOwner.selector);
        vault.setMinICR(1.7e18);

        vm.prank(alice);
        vault.setMinICR(1.7e18);
        _assertEq(vault.minICR(), 1.7e18, "new owner can update");
    }
}
