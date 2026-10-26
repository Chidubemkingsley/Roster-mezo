import {
  BrowserProvider,
  Contract,
  Interface,
  JsonRpcProvider,
  formatUnits,
  getAddress,
  parseUnits,
} from "ethers";
import {
  BOOK_ABI,
  CONFIG,
  ERC20_ABI,
  FACTORY_ABI,
  PRICE_FEED_ABI,
  SERIES_ABI,
  VAULT_ABI,
} from "./config.js";

const E18 = 10n ** 18n;
const LOT_RAW = 10n ** 12n;
const ZERO = "0x0000000000000000000000000000000000000000";

const PAGE = document.body.dataset.page || "home";
const NEEDS = {
  home: { vault: true, listings: false, activity: true },
  trade: { vault: false, listings: false, activity: false },
  secondary: { vault: false, listings: true, activity: false },
  vault: { vault: true, listings: false, activity: false },
  activity: { vault: false, listings: false, activity: true },
}[PAGE] || { vault: true, listings: false, activity: true };

const $ = (id) => document.getElementById(id);
const setText = (id, value) => {
  const node = $(id);
  if (node) node.textContent = value;
};
const el = (tag, className, html) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (html !== undefined) node.innerHTML = html;
  return node;
};

const state = {
  readProvider: null,
  signer: null,
  account: null,
  watch: null,
  selected: CONFIG.series,
  series: [],
  byAddress: new Map(),
  price: null,
  trove: null,
  vault: null,
  listings: [],
  activity: [],
  activityFilter: "all",
  activityToBlock: null,
  premiumPaid: new Map(),
  premiumLoaded: false,
  busy: false,
  refreshing: false,
  readError: null,
};

const SERIES_IFACE = new Interface(SERIES_ABI);
const FACTORY_IFACE = new Interface(FACTORY_ABI);
const BOOK_IFACE = new Interface(BOOK_ABI);
const VAULT_IFACE = new Interface(VAULT_ABI);

const CONTRACTS = [
  {
    role: "Series registry",
    name: "RosterSeriesFactory",
    address: CONFIG.factory,
  },
  {
    role: "Secondary market",
    name: "RosterOrderBook",
    address: CONFIG.orderBook,
  },
  {
    role: "Writer vault",
    name: "RosterTroveWriter",
    address: CONFIG.vault,
  },
  {
    role: "Main series",
    name: "RosterBtcPutSeries",
    address: CONFIG.series,
  },
  {
    role: "Expiry demo",
    name: "RosterBtcPutSeries",
    address: CONFIG.demoSeries,
  },
  {
    role: "Stable asset",
    name: "Mezo MUSD",
    address: CONFIG.musd,
  },
  {
    role: "Exercise asset",
    name: "ERC-20 BTC",
    address: CONFIG.btc,
  },
  {
    role: "Price source",
    name: "Mezo PriceFeed",
    address: CONFIG.priceFeed,
  },
];

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

function toNumber(raw) {
  if (raw === null || raw === undefined) return null;
  try {
    return Number(formatUnits(raw, 18));
  } catch {
    return null;
  }
}

function fmtAmount(raw, maxFractionDigits = 4) {
  const value = toNumber(raw);
  if (value === null || Number.isNaN(value)) return "—";
  if (value === 0) return "0";
  if (Math.abs(value) < 0.001) {
    return value.toLocaleString("en-US", { maximumFractionDigits: 12 });
  }
  return value.toLocaleString("en-US", { maximumFractionDigits: maxFractionDigits });
}

function fmtInt(value) {
  if (value === null || value === undefined) return "—";
  return Number(value).toLocaleString("en-US", { maximumFractionDigits: 0 });
}

function fmtUsd(raw) {
  const value = toNumber(raw);
  if (value === null) return "—";
  return `$${value.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function fmtPct(raw) {
  const value = toNumber(raw);
  if (value === null) return "—";
  return `${(value * 100).toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}

function fmtBtc(raw) {
  const value = toNumber(raw);
  if (value === null) return "—";
  return `${value.toLocaleString("en-US", { maximumFractionDigits: 9 })} BTC`;
}

function fmtDate(timestamp, withTime = false) {
  if (timestamp === null || timestamp === undefined) return "—";
  const date = new Date(Number(timestamp) * 1000);
  const options = withTime
    ? {
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        timeZone: "UTC",
        timeZoneName: "short",
      }
    : { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" };
  return date.toLocaleString("en-GB", options);
}

function shortAddress(address, start = 6, end = 4) {
  if (!address) return "—";
  return `${address.slice(0, start)}…${address.slice(-end)}`;
}

function relativeTime(timestamp) {
  const seconds = Math.max(0, Math.floor(Date.now() / 1000) - Number(timestamp));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

function countdown(timestamp) {
  const seconds = Number(timestamp) - Math.floor(Date.now() / 1000);
  if (seconds <= 0) return "matured";
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `in ${days}d ${hours}h`;
  if (hours > 0) return `in ${hours}h ${minutes}m`;
  return `in ${minutes}m`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function errorMessage(error) {
  const message =
    error?.shortMessage ||
    error?.reason ||
    error?.info?.error?.message ||
    error?.error?.message ||
    error?.message ||
    String(error);
  if (message.length > 220) return `${message.slice(0, 217)}…`;
  return message;
}

// ---------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------

function toast(title, detail, kind = "pending", hash = null) {
  if (!$("toastStack")) return null;
  const node = el("div", `toast is-${kind}`);
  const titleRow = el("div", "toast-title", escapeHtml(title));
  node.append(titleRow);
  if (detail) node.append(el("p", "toast-detail", escapeHtml(detail)));
  if (hash) {
    const link = el(
      "a",
      "toast-link",
      `View transaction <svg class="icon"><use href="#i-external" /></svg>`,
    );
    link.href = `${CONFIG.explorer}/tx/${hash}`;
    link.target = "_blank";
    link.rel = "noreferrer";
    node.append(link);
  }
  $("toastStack").append(node);
  if (kind !== "pending") {
    setTimeout(() => node.remove(), kind === "error" ? 9000 : 6500);
  }
  return node;
}

function removeToast(node) {
  if (node && node.isConnected) node.remove();
}

// ---------------------------------------------------------------------------
// Chain access
// ---------------------------------------------------------------------------

function seriesContract(address, runner = state.readProvider) {
  return new Contract(address, SERIES_ABI, runner);
}

function selectedSeries() {
  return state.byAddress.get(state.selected) || state.series[0] || null;
}

function isMatured(series) {
  if (!series) return false;
  return series.expired || Math.floor(Date.now() / 1000) >= Number(series.expiry);
}

function statusOf(series) {
  if (!series) return "Unknown";
  if (series.expired) return "Expired";
  if (isMatured(series)) return "Matured";
  return "Active";
}

async function safe(read, fallback = null) {
  try {
    return await Promise.race([
      read(),
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error("RPC read timed out")), 12000);
      }),
    ]);
  } catch (error) {
    console.warn("[roster] read failed:", error?.shortMessage || error?.message || error);
    return fallback;
  }
}

function readProvider() {
  if (!state.readProvider) {
    state.readProvider = new JsonRpcProvider(CONFIG.rpcUrl, CONFIG.chainId);
  }
  return state.readProvider;
}

async function connectWallet(interactive = true) {
  if (!window.ethereum) {
    if (interactive) {
      toast(
        "No browser wallet",
        "Install MetaMask or another EVM wallet to transact. Read-only data is still live.",
        "error",
      );
    }
    return false;
  }
  try {
    const browserProvider = new BrowserProvider(window.ethereum);
    if (interactive) {
      await browserProvider.send("eth_requestAccounts", []);
    } else {
      const accounts = await browserProvider.send("eth_accounts", []);
      if (!accounts.length) return false;
    }
    const network = await browserProvider.getNetwork();
    if (network.chainId !== BigInt(CONFIG.chainId)) {
      if (!interactive) return false;
      await switchToMezo();
    }
    const signer = await browserProvider.getSigner();
    const account = await signer.getAddress();
    state.signer = signer;
    state.account = account;
    if (!state.watch || state.watch.toLowerCase() === CONFIG.deployer.toLowerCase()) {
      state.watch = account;
      if ($("watchAddress")) $("watchAddress").value = account;
    }
    renderWalletState();
    await refreshPosition();
    await refreshOwnerConsole();
    await refreshBuyButton();
    await refreshExerciseButton();
    await refreshListButton();
    toast("Wallet connected", `${shortAddress(account)} on Mezo testnet.`, "success");
    return true;
  } catch (error) {
    if (interactive) toast("Wallet connection failed", errorMessage(error), "error");
    return false;
  }
}

async function switchToMezo() {
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chainIdHex }],
    });
  } catch (error) {
    if (error?.code !== 4902) throw error;
    await window.ethereum.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: CONFIG.chainIdHex,
          chainName: CONFIG.chainName,
          nativeCurrency: { name: "Bitcoin", symbol: "BTC", decimals: 18 },
          rpcUrls: [CONFIG.rpcUrl],
          blockExplorerUrls: [CONFIG.explorer],
        },
      ],
    });
  }
}

async function ensureWallet() {
  if (state.signer && state.account) return true;
  return connectWallet(true);
}

async function readTokenBalances(address) {
  if (!address) return { musd: null, btc: null };
  const provider = readProvider();
  const musd = new Contract(CONFIG.musd, ERC20_ABI, provider);
  const btc = new Contract(CONFIG.btc, ERC20_ABI, provider);
  const [musdBalance, btcBalance] = await Promise.all([
    safe(() => musd.balanceOf(address)),
    safe(() => btc.balanceOf(address)),
  ]);
  return { musd: musdBalance, btc: btcBalance };
}

async function approveIfNeeded(tokenAddress, tokenAbi, spender, amount, label) {
  const token = new Contract(tokenAddress, tokenAbi, state.signer);
  const current = await token.allowance(state.account, spender);
  if (current >= amount) return;
  const node = toast(`Approve ${label}`, "Confirm the approval in your wallet.", "pending");
  try {
    const tx = await token.approve(spender, amount);
    await tx.wait();
    removeToast(node);
    toast(`${label} approved`, "Approval confirmed. Continuing…", "success", tx.hash);
  } catch (error) {
    removeToast(node);
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function loadSeriesList() {
  const provider = readProvider();
  const factory = new Contract(CONFIG.factory, FACTORY_ABI, provider);
  let addresses = await safe(() => factory.allSeries());
  if (!addresses || addresses.length === 0) {
    addresses = [CONFIG.series, CONFIG.demoSeries];
  }
  const loaded = [];
  for (const address of addresses) {
    const contract = seriesContract(address, provider);
    const [
      name,
      symbol,
      writer,
      strike,
      premium,
      expiry,
      activeLots,
      totalSupply,
      collateral,
      reserved,
      excess,
      premiumBalance,
      totalDeposited,
      totalPayouts,
      expiryRelease,
      expired,
      decimals,
    ] = await Promise.all([
      safe(() => contract.name()),
      safe(() => contract.symbol()),
      safe(() => contract.writer()),
      safe(() => contract.K_raw()),
      safe(() => contract.premium_per_lot_raw()),
      safe(() => contract.expiry()),
      safe(() => contract.active_lots()),
      safe(() => contract.totalSupply()),
      safe(() => contract.collateral_balance_raw()),
      safe(() => contract.reserved_raw()),
      safe(() => contract.excess_raw()),
      safe(() => contract.premium_balance_raw()),
      safe(() => contract.total_deposited_raw()),
      safe(() => contract.total_payouts_raw()),
      safe(() => contract.expiry_release_raw()),
      safe(() => contract.expired()),
      safe(() => contract.decimals()),
    ]);

    if (name === null && symbol === null && strike === null) continue;
    const strikePerLot = strike === null ? null : strike / 1000000n;
    const item = {
      address,
      contract,
      name: name || shortAddress(address),
      symbol: symbol || "—",
      writer: writer || null,
      strike,
      strikePerLot,
      premium,
      expiry,
      activeLots,
      totalSupply,
      collateral,
      reserved,
      excess,
      premiumBalance,
      totalDeposited,
      totalPayouts,
      expiryRelease,
      expired: Boolean(expired),
      decimals: decimals === null ? null : Number(decimals),
    };
    loaded.push(item);
  }
  state.series = loaded;
  state.byAddress = new Map(loaded.map((item) => [item.address.toLowerCase(), item]));
  if (!state.byAddress.has(state.selected.toLowerCase()) && loaded.length) {
    state.selected = loaded[0].address;
  }
}

async function loadVault() {
  const provider = readProvider();
  const vault = new Contract(CONFIG.vault, VAULT_ABI, provider);
  const [owner, series, troveInfo, idle, reserved, minIcr, gasComp, premiumForwarded, expiryForwarded, deposited, btcBalance] =
    await Promise.all([
      safe(() => vault.owner()),
      safe(() => vault.series()),
      safe(() => vault.troveInfo()),
      safe(() => vault.idleMUSD()),
      safe(() => vault.reservedMUSD()),
      safe(() => vault.minICR()),
      safe(() => vault.musdGasCompensation()),
      safe(() => vault.premiumForwarded()),
      safe(() => vault.expiryForwarded()),
      safe(() => vault.totalDepositedToSeries()),
      safe(() => new Contract(CONFIG.btc, ERC20_ABI, provider).balanceOf(CONFIG.vault)),
    ]);

  state.vault = {
    owner,
    series,
    idle,
    reserved,
    minIcr,
    gasComp,
    premiumForwarded,
    expiryForwarded,
    deposited,
    btcBalance,
  };
  state.trove = troveInfo
    ? {
        collateral: troveInfo[0],
        debt: troveInfo[1],
        icr: troveInfo[2],
        price: troveInfo[3],
        status: Number(troveInfo[4]),
      }
    : null;
}

async function loadPrice() {
  const feed = new Contract(CONFIG.priceFeed, PRICE_FEED_ABI, readProvider());
  state.price = await safe(() => feed.fetchPrice());
}

async function loadListings() {
  const provider = readProvider();
  const book = new Contract(CONFIG.orderBook, BOOK_ABI, provider);
  const next = await safe(() => book.nextListingId());
  if (!next) {
    state.listings = [];
    return;
  }
  const count = Number(next);
  const requests = [];
  for (let id = 1; id < count; id += 1) {
    requests.push(safe(async () => ({ id, listing: await book.getListing(id) })));
  }
  const results = await Promise.all(requests);
  state.listings = results
    .filter((result) => result && result.listing && result.listing.active)
    .map(({ id, listing }) => ({
      id,
      seller: listing[0],
      series: listing[1],
      pricePerLot: listing[2],
      remaining: listing[3],
      active: listing[4],
    }));
}

async function loadActivity() {
  const provider = readProvider();
  const fromBlock = CONFIG.deployBlock;
  const toBlock = await provider.getBlockNumber();
  state.activityToBlock = toBlock;
  const sources = [
    {
      address: CONFIG.factory,
      iface: FACTORY_IFACE,
      kind: "factory",
      icon: "layers",
    },
    {
      address: CONFIG.series,
      iface: SERIES_IFACE,
      kind: "series",
      icon: "spark",
    },
    {
      address: CONFIG.demoSeries,
      iface: SERIES_IFACE,
      kind: "series",
      icon: "spark",
    },
    {
      address: CONFIG.orderBook,
      iface: BOOK_IFACE,
      kind: "book",
      icon: "pulse",
    },
    {
      address: CONFIG.vault,
      iface: VAULT_IFACE,
      kind: "vault",
      icon: "shield",
    },
  ];

  // Mezo's public RPC caps eth_getLogs at a 10,000-block span. Scan in
  // non-overlapping windows so the record keeps working as the chain advances.
  const chunkSize = 9000n;
  const lastBlock = BigInt(toBlock);
  const windows = [];
  for (let start = BigInt(fromBlock); start <= lastBlock; start += chunkSize) {
    const end = start + chunkSize - 1n > lastBlock ? lastBlock : start + chunkSize - 1n;
    windows.push([start, end]);
  }

  const logs = [];
  await Promise.all(
    sources.map(async (source) => {
      for (const [windowStart, windowEnd] of windows) {
        try {
          const found = await provider.getLogs({
            address: source.address,
            fromBlock: windowStart,
            toBlock: windowEnd,
          });
          for (const log of found) {
            let parsed;
            try {
              parsed = source.iface.parseLog({ topics: log.topics, data: log.data });
            } catch {
              continue;
            }
            if (!parsed) continue;
            logs.push({ log, parsed, source });
          }
        } catch {
          // A single window or source failure should not hide the rest of the record.
        }
      }
    }),
  );

  const premiumBySeries = new Map();
  const decorated = [];
  for (const entry of logs) {
    const { log, parsed, source } = entry;
    const address = log.address.toLowerCase();
    if (parsed.name === "Purchased" && source.kind === "series") {
      const current = premiumBySeries.get(address) || 0n;
      premiumBySeries.set(address, current + parsed.args.premium);
    }
    const view = describeEvent(parsed, source.kind, address);
    if (!view) continue;
    decorated.push({
      ...view,
      kind: source.kind,
      icon: source.icon,
      tx: log.transactionHash,
      block: log.blockNumber,
      logIndex: log.index,
      address: log.address,
    });
  }

  const blockNumbers = [...new Set(decorated.map((item) => item.block))];
  const timestamps = new Map();
  await Promise.all(
    blockNumbers.map(async (blockNumber) => {
      const block = await safe(() => provider.getBlock(blockNumber));
      if (block?.timestamp !== undefined) timestamps.set(blockNumber, block.timestamp);
    }),
  );
  for (const item of decorated) {
    item.blockTimestamp = timestamps.get(item.block) || null;
  }

  state.premiumPaid = premiumBySeries;
  state.premiumLoaded = true;
  state.activity = decorated.sort((a, b) => {
    if (a.block !== b.block) return b.block - a.block;
    return (b.logIndex ?? 0) - (a.logIndex ?? 0);
  });
}

function describeEvent(parsed, kind, seriesAddress) {
  const args = parsed.args;
  const seriesName =
    state.byAddress.get(seriesAddress)?.symbol || shortAddress(seriesAddress);

  switch (parsed.name) {
    case "SeriesCreated":
      return {
        title: "Series created",
        detail: `${args.symbol} · strike ${fmtAmount(args.strikeRaw, 0)} MUSD/BTC · expires ${fmtDate(args.expiry)}`,
      };
    case "WriterDeposited":
      return { title: "Writer collateral deposited", detail: `${fmtAmount(args.amount)} MUSD into ${seriesName}` };
    case "Purchased":
      return {
        title: `Purchased ${fmtInt(args.lots)} lots`,
        detail: `${fmtAmount(args.premium)} MUSD premium · buyer ${shortAddress(args.buyer)}`,
      };
    case "Exercised":
      return {
        title: `Exercised ${fmtInt(args.lots)} lots`,
        detail: `${fmtBtc(args.btcAmount)} delivered · ${fmtAmount(args.musdPayout)} MUSD paid`,
      };
    case "SeriesExpired":
      return {
        title: "Series expired",
        detail: `${fmtAmount(args.releasedCollateral)} MUSD released to writer ${shortAddress(args.writer)}`,
      };
    case "PremiumWithdrawn":
      return { title: "Premium withdrawn", detail: `${fmtAmount(args.amount)} MUSD to writer` };
    case "Listed":
      return {
        title: `Listed ${fmtInt(args.lots)} lots`,
        detail: `${fmtAmount(args.pricePerLot, 6)} MUSD/lot · seller ${shortAddress(args.seller)}`,
      };
    case "Filled":
      return {
        title: `Filled ${fmtInt(args.lots)} lots`,
        detail: `${fmtAmount(args.musdPaid)} MUSD to seller · buyer ${shortAddress(args.buyer)}`,
      };
    case "Cancelled":
      return { title: "Ask cancelled", detail: `${fmtInt(args.lotsReturned)} lots returned to seller` };
    case "TroveOpened":
      return {
        title: "Mezo trove opened",
        detail: `${fmtAmount(args.collateral)} native BTC collateral · ${fmtAmount(args.debt)} MUSD debt`,
      };
    case "SeriesFunded":
      return { title: "Series funded", detail: `${fmtAmount(args.amount)} MUSD moved into the series reserve` };
    case "PremiumForwarded":
      return { title: "Premium forwarded", detail: `${fmtAmount(args.amount)} MUSD to vault owner` };
    case "ExpiryReleaseForwarded":
      return { title: "Expiry release forwarded", detail: `${fmtAmount(args.amount)} MUSD to vault owner` };
    case "TroveClosed":
      return { title: "Trove closed", detail: `${fmtAmount(args.collateralReturned)} native BTC returned` };
    case "IdleMUSDWithdrawn":
      return { title: "Idle MUSD withdrawn", detail: `${fmtAmount(args.amount)} MUSD to vault owner` };
    case "BtcWithdrawn":
      return {
        title: "ERC-20 BTC withdrawn",
        detail: `${fmtBtc(args.amount)} to ${shortAddress(args.to)}`,
      };
    case "SeriesBound":
      return { title: "Vault bound to series", detail: shortAddress(args.series, 10, 6) };
    case "CollateralAdded":
      return { title: "Native BTC collateral added", detail: `${fmtAmount(args.amount)} BTC` };
    case "CollateralWithdrawn":
      return { title: "Native BTC collateral withdrawn", detail: `${fmtAmount(args.amount)} BTC` };
    case "MUSDWithdrawnFromTrove":
      return { title: "MUSD borrowed from trove", detail: `${fmtAmount(args.amount)} MUSD` };
    case "DebtRepaid":
      return { title: "Trove debt repaid", detail: `${fmtAmount(args.amount)} MUSD` };
    case "CollateralSurplusClaimed":
      return { title: "Collateral surplus claimed", detail: `${fmtAmount(args.amount)} native BTC` };
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderSeriesTabs() {
  const wrap = $("seriesTabs");
  if (!wrap) return;
  wrap.innerHTML = "";
  for (const series of state.series) {
    const button = el("button", "series-tab");
    button.type = "button";
    button.dataset.address = series.address;
    if (series.address === state.selected) button.classList.add("is-active");
    if (isMatured(series)) button.classList.add("is-matured");
    button.innerHTML = `
      <span class="series-dot"></span>
      <span>${escapeHtml(series.symbol)}</span>
      <small>${fmtDate(series.expiry)}</small>
    `;
    button.addEventListener("click", () => {
      state.selected = series.address;
      renderSeriesTabs();
      renderSelectedSeries();
      refreshPosition();
      refreshBuyButton();
      refreshExerciseButton();
      refreshListButton();
    });
    wrap.append(button);
  }
}

function renderSelectedSeries() {
  const series = selectedSeries();
  if (!series) return;
  const status = statusOf(series);
  const matured = isMatured(series);
  const capacity =
    series.strikePerLot && series.strikePerLot > 0n && series.excess !== null
      ? series.excess / series.strikePerLot
      : 0n;
  const capacityText = matured ? "closed" : `${fmtInt(capacity)} lots left`;
  const strikeText = series.strike ? `$${fmtAmount(series.strike, 0)}` : "—";
  const premiumText =
    series.premium !== null && series.premium !== undefined
      ? `${fmtAmount(series.premium, 6)} MUSD`
      : "—";

  if ($("ticketStatus")) {
    const chip = $("ticketStatus");
    chip.className = "status-chip";
    if (matured) chip.classList.add("is-matured");
    chip.innerHTML = `<span class="live-dot"></span> ${status}`;

    setText("ticketSymbol", series.symbol);
    setText("ticketStrike", strikeText);
    setText("ticketPremium", premiumText);
    setText("ticketExpiry", fmtDate(series.expiry));
    if ($("ticketExpiry")) $("ticketExpiry").title = fmtDate(series.expiry, true);
    setText("ticketCountdown", matured ? "matured" : countdown(series.expiry));
    setText("ticketSpot", state.price ? fmtUsd(state.price) : "—");
    setText("ticketLots", series.activeLots !== null ? fmtInt(series.activeLots) : "—");
    setText("ticketCapacity", capacityText);

    const collateral = series.collateral ? Number(series.collateral) : 0;
    const reserved = series.reserved ? Number(series.reserved) : 0;
    const used = collateral > 0 ? Math.min(100, (reserved / collateral) * 100) : matured ? 100 : 0;
    if ($("ticketMeter")) $("ticketMeter").style.width = `${used}%`;

    const writerLink = $("ticketWriter");
    if (writerLink) {
      writerLink.textContent = shortAddress(series.writer, 8, 6);
      writerLink.href = series.writer
        ? `${CONFIG.explorer}/address/${series.writer}`
        : CONFIG.explorer;
    }
    setText(
      "ticketWriterType",
      series.writer && series.writer.toLowerCase() === CONFIG.vault.toLowerCase()
        ? "Trove-backed"
        : "EOA writer",
    );
  }

  setText("buySeriesName", `${series.name} · ${series.symbol}`);
  setText("listSeriesName", `${series.name} · ${series.symbol}`);
  if ($("buyStatusChip")) {
    $("buyStatusChip").textContent = status;
    $("buyStatusChip").className = `chip ${matured ? "is-matured" : "is-active"}`;
  }

  setText("tradeSeriesName", `${series.name} · ${series.symbol}`);
  setText("tradeStatus", status);
  setText("tradeStrike", `${strikeText} / BTC`);
  setText("tradePremium", `${premiumText} per lot`);
  setText("tradeLotSize", "0.000001 BTC");
  setText("tradeExpiry", fmtDate(series.expiry, true));
  setText("tradeCountdown", matured ? "matured" : countdown(series.expiry));
  setText(
    "tradeCollateral",
    series.collateral !== null ? `${fmtAmount(series.collateral)} MUSD` : "—",
  );
  setText(
    "tradeReserved",
    series.reserved !== null && series.activeLots !== null
      ? `${fmtAmount(series.reserved)} MUSD · ${fmtInt(series.activeLots)} lots`
      : "—",
  );
  setText("tradeCapacity", capacityText);

  setText("landingSeries", series.name);
  setText("landingSymbol", series.symbol);
  setText("landingStrike", `${strikeText} / BTC`);
  setText("landingPremium", `${premiumText} per lot`);
  setText("landingLotSize", "0.000001 BTC");
  setText("landingExpiry", fmtDate(series.expiry, true));
  setText("landingCountdown", matured ? "matured" : countdown(series.expiry));
  setText("landingWriter", shortAddress(series.writer, 8, 6));
  setText(
    "landingCollateral",
    series.collateral !== null ? `${fmtAmount(series.collateral)} MUSD` : "—",
  );
  setText(
    "landingActiveLots",
    series.activeLots !== null ? fmtInt(series.activeLots) : "—",
  );
  setText("landingCapacity", matured ? "closed" : fmtInt(capacity));
  if ($("landingWriter")) $("landingWriter").title = series.writer || "";
  if ($("landingStatus")) {
    $("landingStatus").className = `status-chip${matured ? " is-matured" : ""}`;
    $("landingStatus").innerHTML = `<span class="live-dot"></span> ${status}`;
  }

  const paid = state.premiumPaid.get(series.address.toLowerCase());
  if (paid !== undefined || state.premiumLoaded) {
    setText(
      "statPremium",
      state.premiumLoaded && paid !== undefined ? `${fmtAmount(paid)} MUSD` : "—",
    );
  }

  renderStats(series);
}

function renderStats(series) {
  if (!$("statSpot")) return;
  setText("statSpot", state.price ? fmtUsd(state.price) : "—");
  setText("statSpotSub", state.price ? "Mezo PriceFeed · live" : "price unavailable");
  setText(
    "statCollateral",
    series.collateral !== null ? `${fmtAmount(series.collateral)} MUSD` : "—",
  );
  setText("statSupply", series.totalSupply !== null ? fmtInt(series.totalSupply) : "—");

  const icr = state.trove?.icr;
  const icrText = icr !== null && icr !== undefined ? fmtPct(icr) : "—";
  setText("statIcr", icrText);
  if ($("statIcr") && icr !== null && icr !== undefined) {
    const pct = toNumber(icr) * 100;
    $("statIcr").style.color = pct < 120 ? "var(--red)" : pct < 150 ? "var(--amber)" : "var(--green)";
  }
  if (state.vault?.minIcr) setText("statMinIcr", fmtPct(state.vault.minIcr));
}

function renderBuyQuote() {
  if (!$("buyLots")) return;
  const series = selectedSeries();
  if (!series) return;
  const lots = Number($("buyLots").value);
  const whole = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  const premium = series.premium ? BigInt(whole) * series.premium : 0n;
  const payout = series.strikePerLot ? BigInt(whole) * series.strikePerLot : 0n;
  const btc = BigInt(whole) * LOT_RAW;
  $("buyPremium").textContent = `${fmtAmount(premium)} MUSD`;
  $("buyPayout").textContent = `${fmtAmount(payout)} MUSD`;
  $("buyBtc").textContent = `${fmtAmount(btc, 9)} BTC`;
  const capacity =
    series.strikePerLot && series.strikePerLot > 0n && series.excess !== null
      ? series.excess / series.strikePerLot
      : 0n;
  $("buyCapacity").textContent = `${fmtInt(capacity)} lots`;
  refreshBuyButton();
}

async function refreshBuyButton() {
  if (!$("buyBtn")) return;
  const series = selectedSeries();
  const button = $("buyBtn");
  if (!series) return;
  const lots = Number($("buyLots").value);
  const whole = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  const matured = isMatured(series);
  const capacity =
    series.strikePerLot && series.strikePerLot > 0n && series.excess !== null
      ? series.excess / series.strikePerLot
      : 0n;

  let label = "Connect wallet to buy";
  let disabled = false;
  if (matured) {
    label = "Series matured";
    disabled = true;
  } else if (state.account && series.writer && state.account.toLowerCase() === series.writer.toLowerCase()) {
    label = "Writer cannot buy";
    disabled = true;
  } else if (whole > 0 && BigInt(whole) > capacity) {
    label = "Exceeds remaining capacity";
    disabled = true;
  } else if (whole > 0 && series.premium) {
    label = `Buy ${whole.toLocaleString("en-US")} lots · ${fmtAmount(BigInt(whole) * series.premium)} MUSD`;
  } else if (state.account) {
    label = "Enter lots";
    disabled = true;
  }
  button.textContent = label;
  button.disabled = disabled || state.busy;

  if (state.account) {
    const balances = await readTokenBalances(state.account);
    $("buyWalletMusd").textContent =
      balances.musd !== null ? `${fmtAmount(balances.musd)} MUSD` : "—";
  } else {
    $("buyWalletMusd").textContent = "Not connected";
  }
}

async function refreshPosition() {
  const series = selectedSeries();
  const watch = state.watch;

  if ($("secPositionAddress")) {
    setText(
      "secPositionAddress",
      state.account ? shortAddress(state.account, 6, 4) : watch ? shortAddress(watch, 6, 4) : "No wallet",
    );
  }
  if (!watch || !series) {
    setText("positionAddressChip", "No address");
    setText("listOwned", "— owned");
    return;
  }

  setText("positionAddressChip", shortAddress(watch, 6, 4));
  if ($("positionAddressChip")) $("positionAddressChip").title = watch;
  const balances = await readTokenBalances(watch);
  const lots = await safe(() => series.contract.balanceOf(watch));
  const lotsNumber = lots === null ? 0 : Number(lots);
  const notional = BigInt(lotsNumber) * LOT_RAW;
  const value = series.strikePerLot ? BigInt(lotsNumber) * series.strikePerLot : 0n;

  setText("posLots", lots === null ? "—" : fmtInt(lots));
  setText("posNotional", `${fmtAmount(notional, 9)} BTC notional`);
  setText("posMusd", balances.musd !== null ? `${fmtAmount(balances.musd)} MUSD` : "—");
  setText("posBtc", balances.btc !== null ? fmtBtc(balances.btc) : "—");
  setText("posValue", `${fmtAmount(value)} MUSD`);
  setText("posBtcNeed", fmtBtc(notional));
  setText("listOwned", lots === null ? "— owned" : `${fmtInt(lots)} owned`);

  setText("secPosLots", lots === null ? "—" : fmtInt(lots));
  setText("secPosBtc", balances.btc !== null ? fmtBtc(balances.btc) : "—");
  setText("secPosMusd", balances.musd !== null ? `${fmtAmount(balances.musd)} MUSD` : "—");

  state.position = { lots: lotsNumber, ...balances };
  renderExerciseQuote();
  renderListQuote();
}

function renderExerciseQuote() {
  if (!$("exerciseLots")) return;
  const series = selectedSeries();
  if (!series) return;
  const lots = Number($("exerciseLots").value);
  const whole = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  setText("exerciseBtc", `${fmtAmount(BigInt(whole) * LOT_RAW, 9)} BTC`);
  const payout = series.strikePerLot ? BigInt(whole) * series.strikePerLot : 0n;
  setText("exerciseMusd", `${fmtAmount(payout)} MUSD`);
  refreshExerciseButton();
}

async function refreshExerciseButton() {
  if (!$("exerciseBtn")) return;
  const series = selectedSeries();
  const button = $("exerciseBtn");
  if (!series) return;
  const position = state.position || { lots: 0, btc: null };
  const lots = Number($("exerciseLots").value);
  const whole = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  const matured = isMatured(series);
  const maxByBtc =
    position.btc === null ? 0 : Number(position.btc / LOT_RAW);
  let label = "Connect wallet to exercise";
  let disabled = false;
  if (matured) {
    label = "Series matured";
    disabled = true;
  } else if (!state.account) {
    label = "Connect wallet to exercise";
  } else if (series.writer && state.account.toLowerCase() === series.writer.toLowerCase()) {
    label = "Writer cannot exercise";
    disabled = true;
  } else if (position.lots === 0) {
    label = "No position to exercise";
    disabled = true;
  } else if (whole > 0 && whole > position.lots) {
    label = "Exceeds your position";
    disabled = true;
  } else if (whole > 0 && whole > maxByBtc) {
    label = "Not enough ERC-20 BTC";
    disabled = true;
  } else if (whole > 0) {
    label = `Exercise ${whole.toLocaleString("en-US")} lots · ${fmtAmount(BigInt(whole) * series.strikePerLot)} MUSD`;
  } else {
    label = "Enter lots to exercise";
    disabled = true;
  }
  button.textContent = label;
  button.disabled = disabled || state.busy;
  $("exerciseChip").textContent = matured ? "Closed" : "Manual";
  $("exerciseChip").className = `chip ${matured ? "is-matured" : "chip-soft"}`;
}

function renderListQuote() {
  if (!$("listLots") || !$("listPrice")) return;
  const price = Number($("listPrice").value);
  const lots = Number($("listLots").value);
  const wholeLots = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  if (Number.isFinite(price) && price > 0) {
    try {
      const priceRaw = parseUnits(String(price), 18);
      const total = priceRaw * BigInt(wholeLots);
      setText("listProceeds", `${fmtAmount(total)} MUSD`);
    } catch {
      setText("listProceeds", "— MUSD");
    }
  } else {
    setText("listProceeds", "— MUSD");
  }
  setText("listEscrow", `${wholeLots.toLocaleString("en-US")} lots`);
  refreshListButton();
}

async function refreshListButton() {
  if (!$("listBtn")) return;
  const series = selectedSeries();
  const button = $("listBtn");
  if (!series) return;
  const lots = Number($("listLots").value);
  const whole = Number.isFinite(lots) && lots > 0 ? Math.floor(lots) : 0;
  const price = Number($("listPrice").value);
  const position = state.position || { lots: 0 };
  let label = "Connect wallet to list";
  let disabled = false;
  if (isMatured(series)) {
    label = "Series matured";
    disabled = true;
  } else if (!state.account) {
    label = "Connect wallet to list";
  } else if (series.writer && state.account.toLowerCase() === series.writer.toLowerCase()) {
    label = "Writer cannot list";
    disabled = true;
  } else if (position.lots === 0) {
    label = "No position to list";
    disabled = true;
  } else if (whole <= 0) {
    label = "Enter lots to list";
    disabled = true;
  } else if (whole > position.lots) {
    label = "Exceeds your position";
    disabled = true;
  } else if (!Number.isFinite(price) || price <= 0) {
    label = "Enter an ask price";
    disabled = true;
  } else {
    label = `List ${whole.toLocaleString("en-US")} lots at ${price} MUSD`;
  }
  button.textContent = label;
  button.disabled = disabled || state.busy;
}

function renderWalletState() {
  if (!$("connectLabel") || !$("connectBtn")) return;
  $("connectLabel").textContent = state.account ? shortAddress(state.account, 6, 4) : "Connect wallet";
  $("connectBtn").title = state.account || "Connect wallet";
  $("connectBtn").classList.toggle("is-connected", Boolean(state.account));
}

function renderVault() {
  if (!state.vault) return;
  const vault = state.vault;
  const statusLabels = ["Non-existent", "Active", "Closed", "Liquidated"];
  const trove = state.trove;

  if (vault.minIcr !== null && vault.minIcr !== undefined) {
    setText("minIcr", fmtPct(vault.minIcr));
    setText("vaultHeroMinIcr", fmtPct(vault.minIcr));
  }
  if ($("vaultExplorer")) $("vaultExplorer").href = `${CONFIG.explorer}/address/${CONFIG.vault}`;

  if (trove) {
    const { icr, collateral, debt, price, status } = trove;
    const icrPct = toNumber(icr) * 100;
    const statusLabel = statusLabels[status] || `Status ${status}`;
    const icrLabel = debt === 0n ? "No debt" : fmtPct(icr);
    const icrColor =
      icrPct < 120 ? "var(--red)" : icrPct < 150 ? "var(--amber)" : "var(--green)";

    setText("vaultHeroIcr", icrLabel);
    setText("vaultHeroCollateral", fmtBtc(collateral));
    setText("vaultHeroDebt", `${fmtAmount(debt)} MUSD`);
    setText("vaultHeroStatus", `Status ${statusLabel}`);
    if ($("vaultHeroIcr")) $("vaultHeroIcr").style.color = icrColor;
    if ($("vaultHeroStatusChip")) {
      $("vaultHeroStatusChip").className = `status-chip${status === 1 ? "" : " is-matured"}`;
      $("vaultHeroStatusChip").innerHTML = `<span class="live-dot"></span> ${statusLabel}`;
    }

    setText("landingTroveCollateral", `${fmtAmount(collateral)} native BTC`);
    setText("landingTroveDebt", `${fmtAmount(debt)} MUSD`);
    setText("landingTroveIcr", icrLabel);
    if ($("landingTroveIcr")) $("landingTroveIcr").style.color = icrColor;
    if ($("landingTroveStatus")) {
      $("landingTroveStatus").textContent = statusLabel;
      $("landingTroveStatus").className = "chip";
      if (status === 1) $("landingTroveStatus").classList.add("is-active");
      else if (status === 3) $("landingTroveStatus").classList.add("is-danger");
      else $("landingTroveStatus").classList.add("is-matured");
    }
  } else {
    setText("vaultHeroIcr", "—");
    setText("vaultHeroCollateral", "—");
    setText("vaultHeroDebt", "—");
    setText("vaultHeroStatus", "Status unavailable");
    setText("landingTroveCollateral", "—");
    setText("landingTroveDebt", "—");
    setText("landingTroveIcr", "—");
    if ($("landingTroveStatus")) {
      $("landingTroveStatus").textContent = "Unavailable";
      $("landingTroveStatus").className = "chip chip-soft";
    }
  }

  if (!$("troveIcr")) return;

  setText("vaultOwnerLine", vault.owner ? `Owner ${shortAddress(vault.owner, 8, 6)}` : "Owner —");
  setText("vaultIdle", vault.idle !== null ? `${fmtAmount(vault.idle)} MUSD` : "—");
  setText("vaultReserved", vault.reserved !== null ? `${fmtAmount(vault.reserved)} MUSD` : "—");
  setText("vaultBtc", vault.btcBalance !== null ? fmtBtc(vault.btcBalance) : "—");
  setText(
    "vaultPremium",
    vault.premiumForwarded !== null ? `${fmtAmount(vault.premiumForwarded)} MUSD` : "—",
  );
  setText(
    "vaultRelease",
    vault.expiryForwarded !== null ? `${fmtAmount(vault.expiryForwarded)} MUSD` : "—",
  );
  setText(
    "vaultDeposited",
    vault.deposited !== null ? `${fmtAmount(vault.deposited)} MUSD` : "—",
  );

  if (!trove) {
    setText("troveIcr", "—");
    setText("troveCollateral", "—");
    setText("troveDebt", "—");
    setText("trovePrice", "—");
    setText("troveStatus", "Unavailable");
    return;
  }

  const { icr, collateral, debt, price, status } = trove;
  const icrPct = toNumber(icr) * 100;
  const statusLabel = statusLabels[status] || `Status ${status}`;
  setText("troveIcr", debt === 0n ? "No debt" : fmtPct(icr));
  if ($("troveIcr")) {
    $("troveIcr").className = `health-number${icrPct < 120 ? " is-danger" : icrPct < 150 ? " is-warning" : ""}`;
  }
  setText("troveCollateral", `${fmtAmount(collateral)} native BTC`);
  setText("troveDebt", `${fmtAmount(debt)} MUSD`);
  setText("trovePrice", fmtUsd(price));
  setText("troveStatus", statusLabel);

  if ($("troveStatusChip")) {
    const chip = $("troveStatusChip");
    chip.textContent = statusLabel;
    chip.className = "chip";
    if (status === 1) chip.classList.add("is-active");
    else if (status === 3) chip.classList.add("is-danger");
    else chip.classList.add("is-matured");
  }

  const fillWidth = Number.isFinite(icrPct)
    ? Math.max(2, Math.min(100, ((icrPct - 110) / 90) * 100))
    : 0;
  if ($("healthFill")) {
    $("healthFill").style.width = `${fillWidth}%`;
    $("healthFill").style.background =
      icrPct < 120 ? "var(--red)" : icrPct < 150 ? "var(--amber)" : "var(--green)";
  }
}

async function refreshOwnerConsole() {
  if (!state.vault || !$("ownerChip")) return;
  const isOwner = Boolean(
    state.account && state.vault.owner &&
      state.account.toLowerCase() === state.vault.owner.toLowerCase(),
  );
  $("ownerChip").textContent = isOwner ? "Owner" : "Read only";
  $("ownerChip").className = `chip ${isOwner ? "is-active" : "chip-soft"}`;
  $("ownerHint").textContent = isOwner
    ? "Owner wallet connected. Withdrawals forward to this address."
    : "Connect the vault owner wallet to manage premium, idle MUSD, and ERC-20 BTC.";

  const boundSeries = state.vault.series
    ? state.byAddress.get(String(state.vault.series).toLowerCase())
    : null;
  const premiumReady = isOwner && boundSeries && boundSeries.premiumBalance > 0n;
  $("ownerPremium").disabled = !premiumReady || state.busy;
  $("ownerIdle").disabled = !isOwner || !state.vault.idle || state.vault.idle === 0n || state.busy;
  $("ownerBtc").disabled = !isOwner || !state.vault.btcBalance || state.vault.btcBalance === 0n || state.busy;

  const finalizable =
    isOwner && boundSeries && (boundSeries.expired || isMatured(boundSeries));
  $("ownerFinalize").disabled = !finalizable || state.busy;

  const troveActive = state.trove && state.trove.status === 1;
  const required =
    state.trove && state.vault.gasComp !== null && state.trove.debt > state.vault.gasComp
      ? state.trove.debt - state.vault.gasComp
      : 0n;
  const closeOwner = state.account && isOwner ? state.account : state.vault.owner;
  const ownerBalances = closeOwner
    ? await readTokenBalances(closeOwner)
    : { musd: 0n };
  const available = (state.vault.idle || 0n) + (ownerBalances.musd || 0n);
  const shortfall = required > available ? required - available : 0n;
  const canClose = isOwner && troveActive && required > 0n && shortfall === 0n;
  $("ownerClose").disabled = !canClose || state.busy;
  $("closeTroveNote").textContent = !troveActive
    ? "No active trove"
    : shortfall > 0n
      ? `Needs ${fmtAmount(required)} MUSD · short ${fmtAmount(shortfall)}`
      : `Repay ${fmtAmount(required)} MUSD to close`;
}

function renderListings() {
  const body = $("listingsBody");
  const active = state.listings;
  const totalLots = active.reduce((sum, listing) => sum + Number(listing.remaining), 0);
  const bestPrice = active.reduce(
    (best, listing) => (best === null || listing.pricePerLot < best ? listing.pricePerLot : best),
    null,
  );

  setText("bookHeroAsks", String(active.length));
  setText("bookHeroLots", `${fmtInt(totalLots)} lots`);
  setText("bookHeroBest", bestPrice === null ? "—" : `${fmtAmount(bestPrice, 6)} MUSD/lot`);

  if (!body) return;
  setText(
    "bookOpen",
    active.length
      ? `${active.length} ask${active.length === 1 ? "" : "s"} · ${fmtInt(totalLots)} lots`
      : "0 asks",
  );

  if (active.length === 0) {
    body.innerHTML = `<tr><td colspan="7" class="empty">No open asks. List a position to start one.</td></tr>`;
    return;
  }

  body.innerHTML = "";
  for (const listing of active) {
    const series = state.byAddress.get(listing.series.toLowerCase());
    const price = listing.pricePerLot;
    const total = price * listing.remaining;
    const isSeller = Boolean(
      state.account && state.account.toLowerCase() === listing.seller.toLowerCase(),
    );
    const row = el("tr");
    row.innerHTML = `
      <td class="mono">${listing.id}</td>
      <td><span class="series-tag"><span class="series-dot"></span>${escapeHtml(series?.symbol || shortAddress(listing.series))}</span></td>
      <td class="mono" title="${escapeHtml(listing.seller)}">${shortAddress(listing.seller)}</td>
      <td class="num">${fmtInt(listing.remaining)}</td>
      <td class="num">${fmtAmount(price, 6)}</td>
      <td class="num">${fmtAmount(total)}</td>
      <td class="num"></td>
    `;
    const action = el("button", `table-action${isSeller ? " muted" : ""}`);
    action.type = "button";
    action.textContent = isSeller ? "Cancel" : "Fill all";
    action.title = isSeller ? "Cancel this listing" : `Buy all ${fmtInt(listing.remaining)} lots`;
    action.addEventListener("click", () =>
      isSeller ? cancelListing(listing, action) : fillListing(listing, action),
    );
    row.lastElementChild.append(action);
    body.append(row);
  }
}

function renderActivitySummary() {
  if (!$("activityCount")) return;
  const activity = state.activity;
  setText("activityCount", fmtInt(activity.length));
  setText(
    "activityBlock",
    state.activityToBlock !== null ? Number(state.activityToBlock).toLocaleString("en-US") : "—",
  );
  if (activity.length) {
    const earliest = activity.reduce(
      (min, item) => (item.block < min ? item.block : min),
      activity[0].block,
    );
    setText(
      "activityRange",
      `${Number(earliest).toLocaleString("en-US")}–${Number(state.activityToBlock).toLocaleString("en-US")}`,
    );
    const latest = activity[0];
    setText(
      "activityLatest",
      latest.blockTimestamp
        ? `Latest action ${relativeTime(latest.blockTimestamp)} · block ${Number(latest.block).toLocaleString("en-US")}`
        : `Latest action in block ${Number(latest.block).toLocaleString("en-US")}`,
    );
  } else {
    setText("activityRange", "—");
    setText("activityLatest", "No decoded events in range");
  }
}

function renderActivity() {
  const wrap = $("activityList");
  if (!wrap) return;
  renderActivitySummary();
  const filtered =
    state.activityFilter === "all"
      ? state.activity
      : state.activity.filter((item) => item.kind === state.activityFilter);
  if (filtered.length === 0) {
    wrap.innerHTML = `<div class="empty-state">No matching on-chain activity found.</div>`;
    return;
  }
  wrap.innerHTML = "";
  for (const item of filtered.slice(0, 80)) {
    const row = el("div", "activity-row");
    row.innerHTML = `
      <span class="activity-icon ${item.kind}"><svg class="icon"><use href="#i-${item.icon}" /></svg></span>
      <div class="activity-body">
        <strong>${escapeHtml(item.title)}</strong>
        <span>${escapeHtml(item.detail)}</span>
      </div>
      <div class="activity-meta">
        <strong>${item.blockTimestamp ? relativeTime(item.blockTimestamp) : "—"}</strong>
        <span>block ${Number(item.block).toLocaleString("en-US")}</span>
      </div>
      <a class="activity-link" href="${CONFIG.explorer}/tx/${item.tx}" target="_blank" rel="noreferrer" title="View transaction">
        <svg class="icon"><use href="#i-external" /></svg>
      </a>
    `;
    wrap.append(row);
  }
}

function renderContracts() {
  const wrap = $("contractGrid");
  if (!wrap) return;
  wrap.innerHTML = "";
  for (const contract of CONTRACTS) {
    const card = el("article", "contract-card");
    card.innerHTML = `
      <div class="contract-info">
        <span class="contract-role">${escapeHtml(contract.role)}</span>
        <span class="contract-name">${escapeHtml(contract.name)}</span>
        <span class="mono" title="${escapeHtml(contract.address)}">${escapeHtml(contract.address)}</span>
      </div>
      <div class="contract-actions">
        <button class="icon-btn" type="button" title="Copy address" data-copy="${escapeHtml(contract.address)}">
          <svg class="icon"><use href="#i-copy" /></svg>
        </button>
        <a class="icon-btn" href="${CONFIG.explorer}/address/${contract.address}" target="_blank" rel="noreferrer" title="Open in explorer">
          <svg class="icon"><use href="#i-external" /></svg>
        </a>
      </div>
    `;
    wrap.append(card);
  }
  wrap.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const value = button.dataset.copy;
      try {
        await navigator.clipboard.writeText(value);
        toast("Address copied", shortAddress(value, 10, 8), "success");
      } catch {
        toast("Could not copy", "Select the address manually.", "error");
      }
    });
  });
  setText("deployBlockLabel", `Deployed block ${Number(CONFIG.deployBlock).toLocaleString("en-US")}`);
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

async function buyLots(button) {
  if (!(await ensureWallet())) return;
  const series = selectedSeries();
  const lots = Number($("buyLots").value);
  if (!Number.isInteger(lots) || lots <= 0) {
    toast("Invalid amount", "Enter a positive whole number of lots.", "error");
    return;
  }
  const amount = BigInt(lots);
  if (!series.premium) return;
  const premium = amount * series.premium;
  await withTransaction(button, `Buy ${lots.toLocaleString("en-US")} lots`, async () => {
    await approveIfNeeded(CONFIG.musd, ERC20_ABI, series.address, premium, "MUSD");
    const contract = seriesContract(series.address, state.signer);
    return contract.purchase(amount);
  });
}

async function exerciseLots(button) {
  if (!(await ensureWallet())) return;
  const series = selectedSeries();
  const lots = Number($("exerciseLots").value);
  if (!Number.isInteger(lots) || lots <= 0) {
    toast("Invalid amount", "Enter a positive whole number of lots.", "error");
    return;
  }
  const amount = BigInt(lots);
  const btcNeeded = amount * LOT_RAW;
  await withTransaction(button, `Exercise ${lots.toLocaleString("en-US")} lots`, async () => {
    await approveIfNeeded(CONFIG.btc, ERC20_ABI, series.address, btcNeeded, "ERC-20 BTC");
    const contract = seriesContract(series.address, state.signer);
    return contract.exercise(amount);
  });
}

async function listLots(button) {
  if (!(await ensureWallet())) return;
  const series = selectedSeries();
  const lots = Number($("listLots").value);
  const price = Number($("listPrice").value);
  if (!Number.isInteger(lots) || lots <= 0) {
    toast("Invalid amount", "Enter a positive whole number of lots.", "error");
    return;
  }
  if (!Number.isFinite(price) || price <= 0) {
    toast("Invalid price", "Enter an ask price in MUSD per lot.", "error");
    return;
  }
  const amount = BigInt(lots);
  const priceRaw = parseUnits(String(price), 18);
  await withTransaction(button, `List ${lots.toLocaleString("en-US")} lots`, async () => {
    await approveIfNeeded(series.address, SERIES_ABI, CONFIG.orderBook, amount, "position lots");
    const book = new Contract(CONFIG.orderBook, BOOK_ABI, state.signer);
    return book.list(series.address, amount, priceRaw);
  });
}

async function fillListing(listing, button) {
  if (!(await ensureWallet())) return;
  const total = listing.pricePerLot * listing.remaining;
  await withTransaction(button, `Fill ${fmtInt(listing.remaining)} lots`, async () => {
    await approveIfNeeded(CONFIG.musd, ERC20_ABI, CONFIG.orderBook, total, "MUSD");
    const book = new Contract(CONFIG.orderBook, BOOK_ABI, state.signer);
    return book.fill(listing.id, listing.remaining);
  });
}

async function cancelListing(listing, button) {
  if (!(await ensureWallet())) return;
  await withTransaction(button, `Cancel listing ${listing.id}`, async () => {
    const book = new Contract(CONFIG.orderBook, BOOK_ABI, state.signer);
    return book.cancel(listing.id);
  });
}

async function ownerWithdrawPremium(button) {
  if (!(await ensureWallet())) return;
  await withTransaction(button, "Withdraw premium", async () => {
    const vault = new Contract(CONFIG.vault, VAULT_ABI, state.signer);
    return vault.withdrawPremium();
  });
}

async function ownerWithdrawIdle(button) {
  if (!(await ensureWallet())) return;
  const amount = Number($("ownerIdleAmount").value);
  if (!Number.isFinite(amount) || amount <= 0) {
    toast("Invalid amount", "Enter a positive MUSD amount.", "error");
    return;
  }
  const raw = parseUnits(String(amount), 18);
  await withTransaction(button, "Withdraw idle MUSD", async () => {
    const vault = new Contract(CONFIG.vault, VAULT_ABI, state.signer);
    return vault.withdrawIdleMUSD(raw);
  });
}

async function ownerWithdrawBtc(button) {
  if (!(await ensureWallet())) return;
  const amount = Number($("ownerBtcAmount").value);
  if (!Number.isFinite(amount) || amount <= 0) {
    toast("Invalid amount", "Enter a positive BTC amount.", "error");
    return;
  }
  const raw = parseUnits(String(amount), 18);
  await withTransaction(button, "Withdraw ERC-20 BTC", async () => {
    const vault = new Contract(CONFIG.vault, VAULT_ABI, state.signer);
    return vault.withdrawBtc(state.account, raw);
  });
}

async function ownerFinalize(button) {
  if (!(await ensureWallet())) return;
  await withTransaction(button, "Finalize expired series", async () => {
    const vault = new Contract(CONFIG.vault, VAULT_ABI, state.signer);
    return vault.finalize();
  });
}

async function withTransaction(button, label, action) {
  if (state.busy) return;
  state.busy = true;
  const original = button.textContent;
  button.disabled = true;
  button.classList.add("is-loading");
  const pending = toast(label, "Confirm the transaction in your wallet.", "pending");
  try {
    const tx = await action();
    removeToast(pending);
    const submitted = toast(label, "Transaction submitted. Waiting for confirmation…", "pending", tx.hash);
    const receipt = await tx.wait();
    removeToast(submitted);
    if (receipt?.status === 0) throw new Error("Transaction reverted on-chain.");
    toast(label, "Confirmed on Mezo testnet.", "success", tx.hash);
    await refreshAll();
  } catch (error) {
    removeToast(pending);
    toast(`${label} failed`, errorMessage(error), "error");
  } finally {
    state.busy = false;
    button.classList.remove("is-loading");
    button.textContent = original;
    await refreshAllButtons();
  }
}

async function refreshAllButtons() {
  await refreshBuyButton();
  await refreshExerciseButton();
  await refreshListButton();
  await refreshOwnerConsole();
}

// ---------------------------------------------------------------------------
// Refresh loop
// ---------------------------------------------------------------------------

async function refreshAll() {
  if (state.refreshing) return;
  state.refreshing = true;
  try {
    await Promise.all([loadPrice(), loadSeriesList()]);
    if (NEEDS.vault) await loadVault();
    if (NEEDS.listings) await loadListings();

    if (!state.watch && PAGE === "trade") {
      state.watch = state.account || CONFIG.deployer;
      if ($("watchAddress") && !$("watchAddress").value) {
        $("watchAddress").value = state.watch;
      }
    }

    renderSeriesTabs();
    renderSelectedSeries();
    renderBuyQuote();
    renderVault();
    await refreshPosition();
    renderListings();
    await refreshOwnerConsole();
    await refreshAllButtons();

    if (NEEDS.activity) {
      try {
        await loadActivity();
        renderSelectedSeries();
        renderActivity();
      } catch {
        // Activity is supplementary; never block the trading view.
      }
    }
    state.readError = null;
  } catch (error) {
    if (!state.readError) {
      toast("RPC read failed", errorMessage(error), "error");
      state.readError = error;
    }
  } finally {
    state.refreshing = false;
  }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

function on(id, event, handler, options) {
  const node = $(id);
  if (node) node.addEventListener(event, handler, options);
  return node;
}

function wireEvents() {
  on("connectBtn", "click", () => connectWallet(true));

  document.querySelectorAll(".quick-row button").forEach((button) => {
    button.addEventListener("click", () => {
      if (!$("buyLots")) return;
      $("buyLots").value = button.dataset.lots;
      renderBuyQuote();
    });
  });

  on("buyMax", "click", () => {
    const series = selectedSeries();
    if (!series || !series.strikePerLot || !$("buyLots")) return;
    const capacity = series.excess / series.strikePerLot;
    $("buyLots").value = capacity.toString();
    renderBuyQuote();
  });

  on("exerciseMax", "click", () => {
    if (!$("exerciseLots")) return;
    const position = state.position || { lots: 0, btc: 0n };
    const byBtc = position.btc === null ? 0 : Number(position.btc / LOT_RAW);
    $("exerciseLots").value = String(Math.min(position.lots, byBtc));
    renderExerciseQuote();
  });

  on("listMax", "click", () => {
    if (!$("listLots")) return;
    $("listLots").value = String(state.position?.lots || 0);
    renderListQuote();
  });

  on("buyLots", "input", renderBuyQuote);
  on("exerciseLots", "input", renderExerciseQuote);
  on("listLots", "input", renderListQuote);
  on("listPrice", "input", renderListQuote);

  on("buyBtn", "click", (event) => buyLots(event.currentTarget));
  on("exerciseBtn", "click", (event) => exerciseLots(event.currentTarget));
  on("listBtn", "click", (event) => listLots(event.currentTarget));
  on("refreshListings", "click", async () => {
    await loadListings();
    renderListings();
    toast("Order book refreshed", "Open asks reloaded from Mezo testnet.", "success");
  });

  on("watchBtn", "click", async () => {
    if (!$("watchAddress")) return;
    const input = $("watchAddress").value.trim();
    if (!input) {
      state.watch = state.account || CONFIG.deployer;
    } else {
      try {
        state.watch = getAddress(input);
      } catch {
        toast("Invalid address", "Enter a checksummed EVM address.", "error");
        return;
      }
    }
    await refreshPosition();
    await refreshOwnerConsole();
  });

  on("watchAddress", "keydown", (event) => {
    if (event.key === "Enter") $("watchBtn")?.click();
  });

  on("ownerPremium", "click", (event) => ownerWithdrawPremium(event.currentTarget));
  on("ownerIdle", "click", (event) => ownerWithdrawIdle(event.currentTarget));
  on("ownerBtc", "click", (event) => ownerWithdrawBtc(event.currentTarget));
  on("ownerFinalize", "click", (event) => ownerFinalize(event.currentTarget));
  on("ownerClose", "click", async (event) => {
    if (!(await ensureWallet())) return;
    await withTransaction(event.currentTarget, "Close trove", async () => {
      const vault = new Contract(CONFIG.vault, VAULT_ABI, state.signer);
      return vault.closeTrove();
    });
  });

  on("activityFilters", "click", (event) => {
    const button = event.target.closest("[data-filter]");
    if (!button) return;
    state.activityFilter = button.dataset.filter;
    document.querySelectorAll("#activityFilters .filter").forEach((filter) => {
      filter.classList.toggle("is-active", filter === button);
    });
    renderActivity();
  });

  window.addEventListener("scroll", () => {
    document.querySelector(".site-header")?.classList.toggle("is-scrolled", window.scrollY > 8);
  });

  setInterval(() => {
    const series = selectedSeries();
    if (series && !isMatured(series) && $("ticketCountdown")) {
      $("ticketCountdown").textContent = countdown(series.expiry);
    }
    if (state.activity.length && $("activityList")) renderActivity();
  }, 30000);

  setInterval(refreshAll, 45000);
}

async function restoreWallet() {
  if (!window.ethereum) return;
  try {
    const accounts = await window.ethereum.request({ method: "eth_accounts" });
    if (!accounts || accounts.length === 0) return;
    const chainId = await window.ethereum.request({ method: "eth_chainId" });
    if (Number.parseInt(chainId, 16) !== CONFIG.chainId) return;
    await connectWallet(false);
  } catch {
    // A read-only page is still useful without a wallet.
  }
}

function init() {
  readProvider();
  renderContracts();
  wireEvents();
  if ($("watchAddress")) {
    $("watchAddress").value = CONFIG.deployer;
    state.watch = CONFIG.deployer;
  }
  if (window.ethereum) {
    window.ethereum.on?.("accountsChanged", () => window.location.reload());
    window.ethereum.on?.("chainChanged", () => window.location.reload());
  }
  refreshAll();
  restoreWallet();
}

try {
  init();
} catch (error) {
  console.error("[roster] init failed:", error);
}
