// Live Mezo testnet deployment. Addresses are public; keys never belong in the app.
export const CONFIG = {
  chainId: 31611,
  chainIdHex: "0x7b7b",
  chainName: "Mezo Testnet",
  rpcUrl: "https://rpc.test.mezo.org",
  explorer: "https://explorer.test.mezo.org",

  musd: "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503",
  btc: "0x7b7C000000000000000000000000000000000000",
  priceFeed: "0x86bCF0841622a5dAC14A313a15f96A95421b9366",

  factory: "0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F",
  orderBook: "0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25",
  vault: "0x214e2316EAEeE24c1dc5d8433329fFC7544DA331",
  series: "0xC23167867baAF830D586598DE0634E26fD895b92",

  deployer: "0x90356CF97B3BF1749A604d3F89b3DF3602A459E3",
  buyer: "0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5",

  deployBlock: 0xf99f8c,
  demoSeries: "0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43",

  links: {
    repo: "https://github.com/",
    mezo: "https://mezo.org",
  },
};

export const SERIES_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function writer() view returns (address)",
  "function musd() view returns (address)",
  "function btc() view returns (address)",
  "function K_raw() view returns (uint256)",
  "function strike_per_lot_raw() view returns (uint256)",
  "function premium_per_lot_raw() view returns (uint256)",
  "function expiry() view returns (uint256)",
  "function LOT_SIZE_RAW() view returns (uint256)",
  "function total_deposited_raw() view returns (uint256)",
  "function total_payouts_raw() view returns (uint256)",
  "function expiry_release_raw() view returns (uint256)",
  "function collateral_balance_raw() view returns (uint256)",
  "function reserved_raw() view returns (uint256)",
  "function excess_raw() view returns (uint256)",
  "function premium_balance_raw() view returns (uint256)",
  "function active_lots() view returns (uint256)",
  "function expired() view returns (bool)",
  "function deposit(uint256)",
  "function purchase(uint256)",
  "function exercise(uint256)",
  "function expire()",
  "function withdrawPremium()",
  "event WriterDeposited(address indexed writer, uint256 amount)",
  "event Purchased(address indexed buyer, uint256 lots, uint256 premium, uint256 reserve)",
  "event Exercised(address indexed holder, uint256 lots, uint256 btcAmount, uint256 musdPayout)",
  "event SeriesExpired(address indexed writer, uint256 releasedCollateral)",
  "event PremiumWithdrawn(address indexed writer, uint256 amount)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)",
];

export const FACTORY_ABI = [
  "function seriesCount() view returns (uint256)",
  "function seriesAt(uint256) view returns (address)",
  "function allSeries() view returns (address[])",
  "function isSeries(address) view returns (bool)",
  "event SeriesCreated(address indexed series, address indexed writer, uint256 strikeRaw, uint256 premiumPerLotRaw, uint256 expiry, string name, string symbol)",
];

export const BOOK_ABI = [
  "function nextListingId() view returns (uint256)",
  "function getListing(uint256) view returns (tuple(address seller, address series, uint256 pricePerLot, uint256 remaining, bool active))",
  "function list(address,uint256,uint256) returns (uint256)",
  "function fill(uint256,uint256)",
  "function cancel(uint256)",
  "event Listed(uint256 indexed listingId, address indexed seller, address indexed series, uint256 lots, uint256 pricePerLot)",
  "event Filled(uint256 indexed listingId, address indexed buyer, uint256 lots, uint256 musdPaid)",
  "event Cancelled(uint256 indexed listingId, uint256 lotsReturned)",
];

export const VAULT_ABI = [
  "function owner() view returns (address)",
  "function series() view returns (address)",
  "function seriesBound() view returns (bool)",
  "function isTroveActive() view returns (bool)",
  "function idleMUSD() view returns (uint256)",
  "function reservedMUSD() view returns (uint256)",
  "function minICR() view returns (uint256)",
  "function musdGasCompensation() view returns (uint256)",
  "function premiumForwarded() view returns (uint256)",
  "function expiryForwarded() view returns (uint256)",
  "function totalDepositedToSeries() view returns (uint256)",
  "function troveInfo() view returns (uint256 collateral, uint256 debt, uint256 icr, uint256 price, uint8 status)",
  "function seriesState() view returns (uint256 collateral, uint256 premium, uint256 activeLots, bool expired)",
  "function withdrawPremium()",
  "function withdrawIdleMUSD(uint256)",
  "function withdrawBtc(address,uint256)",
  "function finalize() returns (uint256,uint256)",
  "function closeTrove()",
  "function repay(uint256,address,address)",
  "event SeriesBound(address indexed series)",
  "event TroveOpened(uint256 collateral, uint256 debt, uint256 seriesDeposit)",
  "event SeriesFunded(uint256 amount)",
  "event CollateralAdded(uint256 amount)",
  "event CollateralWithdrawn(uint256 amount)",
  "event MUSDWithdrawnFromTrove(uint256 amount)",
  "event DebtRepaid(uint256 amount)",
  "event PremiumForwarded(uint256 amount)",
  "event ExpiryReleaseForwarded(uint256 amount)",
  "event TroveClosed(uint256 collateralReturned)",
  "event CollateralSurplusClaimed(uint256 amount)",
  "event BtcWithdrawn(address indexed to, uint256 amount)",
  "event IdleMUSDWithdrawn(uint256 amount)",
];

export const ERC20_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
  "function transfer(address,uint256) returns (bool)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
];

export const PRICE_FEED_ABI = ["function fetchPrice() view returns (uint256)"];
