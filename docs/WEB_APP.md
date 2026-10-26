# Web Application

**Path:** [`../app`](../app)
**Stack:** Vite 7 + ethers 6, static ES modules
**Network:** Mezo testnet, chain ID 31611
**Status:** implemented; production build passes; five pages loaded read-only in headless
Chrome at desktop and mobile widths. **No wallet transaction has been performed through
the UI.** Screenshots are in [`screenshots/`](screenshots/). The browser pass predates the
position wrapper and Mezo Pools integration; the app does **not** surface the wrapper or
the wrapper/MUSD pool. Those are verified through `cast` and the explorer and recorded in
[`COMPOSABILITY.md`](COMPOSABILITY.md).

This document describes the multi-page application and every interaction that is wired
in the current tree. It is written against `app/index.html`, `app/trade.html`,
`app/secondary.html`, `app/vault.html`, `app/activity.html`, `app/src/config.js`,
`app/src/main.js`, and `app/src/styles.css`. If the UI and this document disagree, the
code and the on-chain state win.

---

## 1. What the app is

A static, read-first dapp for the Roster Mezo testnet deployment. It is a **multi-page
application**, not a single-page app: each functional area has its own HTML entry and
the shared module changes behavior from `body[data-page]`.

The app:

- reads live series, vault, trove, order-book, token, and price-feed data directly from
  the public Mezo RPC;
- works read-only without a wallet;
- connects an injected EVM wallet for purchases, exercises, listings, fills, cancels,
  and vault-owner actions;
- checks and, if needed, adds/switches to chain 31611;
- never asks for a private key, seed phrase, or server login;
- has no backend, database, account system, custody, analytics, or order matching.

The app is not a general-purpose exchange. It is a focused interface for the deployed
main series, the expired demo series, the shared order book, and the writer vault. It does
**not** expose the position wrapper or the Mezo Pools wrapper/MUSD pool; those exist
outside Roster's UI and are documented in [`COMPOSABILITY.md`](COMPOSABILITY.md).

### 1.1 Page map

| Page | Entry | Role |
| --- | --- | --- |
| Landing | `index.html` | Long-form explanation and live overview; links to the four functional pages |
| Trade | `trade.html` | Primary purchase, position inspection, and exercise |
| Secondary | `secondary.html` | List, browse, fill, and cancel escrowed asks |
| Vault | `vault.html` | Trove health, vault accounting, and owner actions |
| Activity | `activity.html` | Decoded on-chain events and the contract directory |

The landing page deliberately does **not** duplicate the buy, list, exercise, or owner
control panels. Those actions live on their dedicated pages. The landing page contains
the live ticket and stat strip, the mechanism and risk narrative, live terms, and links
to the functional pages.

### 1.2 Build shape

```text
app/
├── index.html
├── trade.html
├── secondary.html
├── vault.html
├── activity.html
├── package.json
├── vite.config.js          # five Rollup inputs
└── src/
    ├── config.js           # addresses, ABIs, chain config
    ├── main.js             # page-aware reads, wallet, actions, rendering
    └── styles.css          # visual system and responsive rules
```

`vite.config.js` sets `base: "./"`, so the built pages can be served from a subdirectory
without rewriting asset URLs. The production build emits five HTML files plus one shared
JS bundle and one shared stylesheet.

---

## 2. Global shell

### 2.1 Header

- **Roster brand** links to `index.html`.
- **Page navigation:** Trade, Secondary, Vault, Activity. The current page receives
  `.is-active` and an orange marker.
- **Network pill:** “Mezo Testnet” with a live dot.
- **Connect wallet button:** opens the injected wallet, requests accounts, and displays
  the truncated connected address after connection.
- The header is responsive. At narrow widths the navigation stays visible as a second
  row; there is no hidden hamburger menu.

### 2.2 Wallet behavior

- Uses `window.ethereum` through ethers `BrowserProvider`.
- On connect, checks `chainId`; if not `31611`, tries `wallet_switchEthereumChain`, then
  `wallet_addEthereumChain` with the Mezo RPC and explorer if the chain is unknown.
- Silently restores an already-authorized wallet only when it is already on chain 31611.
  It does not prompt on page load.
- Reloads the page when the wallet account or chain changes.
- There is no explicit “disconnect” control. The user disconnects through the wallet.
- If no wallet exists, read-only data still works and transaction buttons explain that a
  wallet is needed.
- The app never requests a private key or seed phrase.

### 2.3 Toasts

- Bottom-right notification stack.
- Pending, success, and error states.
- Pending transactions show a spinner.
- Confirmed transactions include an explorer link.
- Errors are shortened but not hidden; the wallet/RPC message is shown.
- Toasts are dismissed automatically or by the close control.

### 2.4 Read-only mode

- The app loads every series, vault, trove, order-book listing, token balance, and
  activity record without a wallet.
- Any address can be entered in the position viewer.
- The default watched address is the deployer
  `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3`; connecting a wallet that is still
  using the default switches the viewer to the connected account.
- A user can inspect another address without connecting.

### 2.5 Page-aware loading

`main.js` defines a `NEEDS` map:

| Page | Vault | Listings | Activity |
| --- | --- | --- | --- |
| Landing | yes | no | yes |
| Trade | no | no | no |
| Secondary | no | yes | no |
| Vault | yes | no | no |
| Activity | no | no | yes |

Every renderer checks that its target element exists before writing, so one shared
module can serve all five documents without page-specific bundles.

---

## 3. Landing page

### 3.1 Hero and live ticket

- **Eyebrow:** “Live on Mezo testnet / Wave 1”.
- **Headline:** “Own the downside. Settle in MUSD.”
- **Lede:** a fixed-strike, fixed-expiry BTC put series collateralized in MUSD and
  funded through a native-BTC Mezo trove.
- **Primary button:** “Open trading” links to `trade.html`.
- **Secondary button:** “Read the mechanism” scrolls to the mechanism section.
- **Footline:** one lot = 0.000001 BTC; ERC-20 BTC settlement; Mezo price feed.

The live ticket reflects the selected series. The default is the main series.

| Element | Meaning |
| --- | --- |
| Status chip | Active, Matured, or Expired |
| Symbol | e.g. `rBTC-PUT-T` |
| Strike | MUSD per BTC, e.g. `$80,000` |
| Premium | MUSD per lot |
| Expiry | Date in UTC |
| Countdown | Time remaining, updated on a timer |
| BTC spot | Live `PriceFeed.fetchPrice()` |
| Active lots | `active_lots()` |
| Capacity left | Unreserved `excess_raw / strike_per_lot_raw` |
| Utilization meter | `reserved_raw / collateral_balance_raw` |
| Writer | Explorer-linked writer address |
| Writer type | “Trove-backed” if the writer is the vault, otherwise “EOA writer” |

Status behavior:

- **Active:** before expiry and not expired.
- **Matured:** current time is at/after expiry but `expire()` has not been called.
- **Expired:** `expired() == true`; collateral has been released and tokens are frozen.

### 3.2 Stat strip

| Stat | Source |
| --- | --- |
| BTC spot | Mezo PriceFeed |
| Series collateral | `collateral_balance_raw()` |
| Premium paid | Sum of `Purchased` event premiums for the selected series, from the deployment block |
| Trove health | `troveInfo().icr`, colored green/amber/red at 150%/120% |
| Position tokens | `totalSupply()` |

If event logs are unavailable, premium paid shows “—” rather than a fabricated number.

### 3.3 Editorial sections

The rest of the landing page is intentionally long-form:

1. **“A put reduced to fixed terms”** — three cards: immutable strike, timestamp expiry,
   and the ask-book exit.
2. **“Four contracts. One payoff”** — factory, series, order book, and trove vault, with
   a four-step register/fund/buy/exercise-or-exit flow.
3. **“The terms, without the marketing”** — live main-series terms and a writer-trove
   summary, including strike, premium, expiry, lot size, collateral, active lots,
   capacity, vault collateral, debt, ICR, and a link to the vault page.
4. **“Locked collateral is not exercise inventory”** — separate cards for locked trove
   collateral and liquid ERC-20 BTC settlement, plus an explicit no-conversion notice.
5. **“The trove is the writer. The debt is real”** — collateral posted, MUSD borrowed,
   debt and interest, liquidation exposure, and the separation from the series reserve.
6. **“An ask book, not a promise of liquidity”** — escrow, direct MUSD payment, maturity
   freeze, and the absence of a synthetic bid.
7. **“From registration to final release”** — six lifecycle steps: series created,
   writer deposit, purchases, secondary ask book, exercise, and expiry/finalization.
8. **“Four pages, one on-chain source”** — cards linking to Trade, Secondary, Vault, and
   Activity.
9. **“Read it from the chain”** — verification guidance, explorer links, and the testnet
   / audit / asset-separation disclosures.

The landing page reads live data and has no transaction controls. The dedicated pages
carry the actions.

---

## 4. Trade page

The Trade page is the primary-market interface. It is split into several live blocks.

### 4.1 Series selector

- Populated from `factory.allSeries()`.
- Falls back to the hard-coded main and demo series if the factory read fails.
- Each tab shows the symbol and expiry date, with active/matured styling.
- The default selection is the main series.
- Selecting a tab updates the ticket, buy panel, position viewer, exercise panel, and
  series facts on this page. It does not change the vault's bound series.

The live deployment has two series:

- main series `0xC231…5b92` — active;
- demo series `0xCC6b…FA43` — expired expiry demonstration.

### 4.2 Buy position panel

**Header:** series name and symbol; status chip.

**Inputs:**

- **Lots** — positive whole number.
- **MAX** — sets the maximum number of lots the current excess collateral can reserve.
- **Quick buttons** — 10, 25, 50, 100 lots.

**Quote:**

| Field | Calculation |
| --- | --- |
| Premium due | `lots × premium_per_lot_raw` |
| Strike payout if exercised | `lots × strike_per_lot_raw` |
| BTC delivered if exercised | `lots × 1e12` raw ERC-20 BTC |
| Series capacity left | `excess_raw / strike_per_lot_raw` |
| Wallet MUSD | Connected wallet's MUSD balance |

**Button states:**

- “Connect wallet to buy”
- “Buy N lots · X MUSD”
- “Enter lots”
- “Exceeds remaining capacity”
- “Writer cannot buy”
- “Series matured”

**Action:**

1. Ensure a wallet is connected.
2. Validate a positive whole lot count.
3. Approve exact MUSD to the series if the current allowance is insufficient.
4. Call `purchase(lots)`.
5. Show pending, success, or error toast with explorer link.
6. Refresh series, position, vault, listings, and activity as needed.

**Fine print:** premium is non-refundable; exercise is manual and must happen before
maturity; transfers freeze at expiry.

### 4.3 Your position panel

**Address viewer:**

- Input accepts any EVM address.
- **Load** button or Enter validates the address and reads positions.
- Chip shows the truncated watched address.
- Default is the deployer; connecting a wallet can switch the viewer to the connected
  account.

**Readouts:**

| Field | Meaning |
| --- | --- |
| Position | `series.balanceOf(watched)` lots |
| BTC notional | lots × 0.000001 BTC |
| MUSD balance | watched address's MUSD |
| ERC-20 BTC balance | watched address's ERC-20 BTC |
| Value at strike | lots × strike per lot |
| BTC to exercise all | lots × 0.000001 BTC |

### 4.4 Exercise panel

- Lots input and MAX.
- MAX is the smaller of position lots and the address's ERC-20 BTC / lot size.
- Quote shows BTC delivered and MUSD received.
- Button states include connect, enter lots, exceed position, not enough BTC, writer
  cannot exercise, and series matured.
- Action approves exact ERC-20 BTC to the series if needed, then calls `exercise(lots)`.
- Fine print explains that the writer receives ERC-20 BTC and the series pays exact
  MUSD.

The viewer does not transfer position tokens. Transfers and listings are handled through
the Secondary page.

### 4.5 Series facts and payoff

The page repeats the fixed terms in a compact table:

- strike;
- premium per lot;
- expiry and countdown;
- lot size;
- collateral;
- reserved amount;
- remaining capacity.

A separate payoff block explains that a position pays the difference between the fixed
strike and the market price only if the holder chooses to exercise, and that exercise
requires the holder to deliver ERC-20 BTC. It does not claim automatic settlement,
guaranteed profit, or a liquid market.

---

## 5. Secondary page

### 5.1 Live ask summary

The hero shows:

| Field | Meaning |
| --- | --- |
| Open listings | Number of active asks across all series |
| Lots for sale | Sum of remaining lots |
| Lowest ask | Lowest price per lot, or “—” if empty |

The summary is book-wide, not filtered to the selected series. The page notes that the
book is ask-only: no bids, no matching engine, no fees, and no promise of a fill.

### 5.2 Series selector and compact position

- The series tabs select the series used by the list form and the compact position card.
- The compact card shows the watched address's position, MUSD balance, ERC-20 BTC
  balance, and position lots.
- The secondary page has its own watched address; it is not persisted across page
  navigation.

### 5.3 List a position panel

**Inputs:**

- Lots to escrow, with MAX equal to the watched address's position.
- Ask price in MUSD per lot.

**Quote:**

- Gross proceeds = lots × price.
- Escrow = lots.

**Button states:**

- connect wallet;
- enter lots;
- enter an ask price;
- exceed position;
- writer cannot list;
- series matured;
- list action label.

**Action:**

1. Approve exact position tokens to the order book if needed.
2. Call `book.list(series, lots, pricePerLot)`.
3. Show toast and refresh listings.

**Fine print:** listings must be cancelled before maturity; escrowed lots cannot be
exercised while listed.

### 5.4 Open asks table

**Summary:** number of open asks and total lots.

**Columns:**

| Column | Meaning |
| --- | --- |
| # | Listing ID |
| Series | Symbol tag |
| Seller | Truncated seller address |
| Lots | Remaining lots |
| Price | MUSD per lot |
| Total | Remaining × price |
| Action | Fill all or Cancel |

**Behavior:**

- Reads `nextListingId()` and `getListing(id)` for every ID.
- Shows active listings only.
- **Fill all** (for non-sellers): approves exact MUSD to the book if needed, then calls
  `fill(listingId, remaining)`. The contract supports partial fills, but this UI fills
  the entire remaining amount. There is no partial-fill input.
- **Cancel** (for the seller): calls `cancel(listingId)` and returns remaining lots.
- **Refresh** reloads the book.
- Empty state: “No open asks.”
- A fill pays MUSD directly from buyer to seller; Roster never custodies secondary
  proceeds.

The live deployment currently has listing 1: seller is the generated buyer, 25 lots at
0.002 MUSD per lot, active.

### 5.5 Settlement rules

The page explains four rules:

1. The seller approves the book and escrows the lots.
2. The buyer approves MUSD and pays the seller directly.
3. A fill transfers the position lots to the buyer.
4. Listings close at maturity; a seller who does not cancel before expiry cannot
   recover escrow.

There is no bid side, no order matching, no fee, no keeper, and no guarantee that an ask
will be filled.

---

## 6. Vault page

### 6.1 Trove health hero

The hero shows the vault's live trove:

- status chip (active, closed, liquidated, or unavailable);
- ICR as a percentage;
- application minimum ICR;
- native BTC collateral;
- MUSD debt;
- the debt-moves-with-interest warning.

Health color thresholds are green at/above 150%, amber from 120% to 150%, and red below
120%. The 150% figure is the application minimum, not a Mezo guarantee. The Mezo
liquidation MCR is 110%.

### 6.2 Trove health panel

| Field | Source |
| --- | --- |
| Native BTC collateral | `troveInfo().collateral` |
| Trove debt | `troveInfo().debt` |
| BTC price | `troveInfo().price` |
| Borrowing status | `troveInfo().status` mapped to non-existent/active/closed/liquidated |
| Health bar | ICR mapped from 110% to 200%+ |

The warning box states that debt accrues interest, a BTC fall or debt rise can liquidate,
closing requires repaying the full debt, and the series reserve is not a promise of free
collateral.

### 6.3 Vault balances

| Field | Meaning |
| --- | --- |
| Idle MUSD | Withdrawable, unreserved vault MUSD |
| Reserved for series release | MUSD received from an expired series but not forwarded |
| ERC-20 BTC held | Exercise proceeds held by the vault |
| Premium forwarded | Cumulative premium forwarded to the owner |
| Expiry release forwarded | Cumulative expiry release forwarded |
| Cumulative deposited to series | `totalDepositedToSeries()` |

This panel is about the vault, not the selected series. Selecting the demo series on
another page does not change the vault's bound series.

### 6.4 Owner console

Read-only unless the connected wallet equals `vault.owner()`.

**Actions:**

1. **Withdraw premium** — calls `vault.withdrawPremium()` on the vault's bound series.
   Enabled only when the owner is connected and the bound series has premium.
2. **Withdraw idle MUSD** — amount input; calls `vault.withdrawIdleMUSD(amount)`.
   Enabled only for the owner with nonzero idle MUSD.
3. **Withdraw ERC-20 BTC** — amount input; calls `vault.withdrawBtc(owner, amount)`.
   Enabled only for the owner with nonzero ERC-20 BTC.
4. **Finalize expired series** — calls `vault.finalize()`. Enabled only for the owner
   when the vault's bound series is matured/expired. It is not enabled merely because
   the selected demo series is expired.
5. **Close trove** — calls `vault.closeTrove()`. Disabled unless the owner is connected,
   the trove is active, and the vault's idle MUSD plus the vault owner's MUSD covers the
   required repayment (debt minus the 200 MUSD gas compensation). The note shows the
   required amount and shortfall. It counts the current vault owner's MUSD even when the
   viewer is disconnected; this is a read-only estimate, not a promise that the owner
   will keep that balance.

The owner console does **not** expose add collateral, borrow more, repay, deposit more
into the series, or transfer vault ownership. Those functions exist in the contract but
are not wired into the UI.

### 6.5 Accounting rules and limits

The page explains:

- borrowed MUSD becomes the series reserve;
- premium is a separate bucket;
- ERC-20 BTC exercise proceeds move to the vault;
- unsold reserve returns to the writer only through the series expiry path;
- the trove debt is not automatically repaid by the series reserve;
- closing the trove does not automatically close the series;
- the live trove cannot be closed with the current MUSD balance.

The limits panel states that there is one bound series per vault, that the application
minimum ICR is 150% while Mezo's MCR is 110%, and that the owner remains exposed to
interest and liquidation.

---

## 7. Activity page

### 7.1 Event summary

- Number of decoded events in the scanned range.
- Latest scanned block.
- Block range covered.
- Latest decoded action and its relative time.
- Note that the log is assembled from public RPC logs and decoded locally; the explorer
  remains the canonical record.

### 7.2 Filters

- **All**
- **Series** — factory-created series events
- **Book** — listings, fills, cancellations
- **Vault** — trove and vault events
- **Factory** — series registration

The filter is client-side and does not rescan the chain.

### 7.3 Decoded log

The feed scans from the recorded deployment block to the current block. Mezo's public RPC
limits `eth_getLogs` to a 10,000-block span, so the app scans in non-overlapping
9,000-block windows. A failed window or source is skipped so the rest of the record still
renders.

Each row shows:

- event icon/category;
- human-readable title and detail;
- relative time and block number;
- explorer transaction link.

Decoded event families include:

- `SeriesCreated`, `SeriesBound`;
- `WriterDeposited`, `Purchased`, `Exercised`, `SeriesExpired`, `PremiumWithdrawn`;
- `Listed`, `Filled`, `Cancelled`;
- `TroveOpened`, `SeriesFunded`, `CollateralAdded`, `CollateralWithdrawn`,
  `MUSDWithdrawnFromTrove`, `DebtRepaid`, `TroveClosed`, `CollateralSurplusClaimed`;
- `PremiumForwarded`, `ExpiryReleaseForwarded`, `IdleMUSDWithdrawn`, `BtcWithdrawn`.

The feed is limited to 80 displayed rows. There is no backend indexer, pagination, search,
or CSV export. Expiry and interest do not produce events of their own; the page reflects
emitted events, not every state change.

### 7.4 Contract directory

Eight cards:

- series factory;
- order book;
- trove vault;
- main series;
- demo series;
- MUSD;
- ERC-20 BTC;
- Mezo PriceFeed.

Each card shows role, contract name, full address, a copy button, and an explorer link.
The section also shows the deployment block.

### 7.5 Verification guidance

The page explains how to:

- copy an address;
- open the transaction on the explorer;
- match the recorded event to the contract state;
- read the series and vault directly if the UI is unavailable.

It explicitly says the app is a convenience view, not the source of truth.

---

## 8. Risk disclosures and footer

Three explicit disclosures appear in the shared footer:

1. **Testnet prototype, not audited.** No audit or independent review; do not use real
   funds.
2. **Two BTC accounting paths.** Trove collateral is locked; ERC-20 BTC is liquid
   exercise inventory. Roster does not convert locked collateral into exercise inventory.
3. **Trove debt is an obligation.** Interest accrues; liquidation is possible; series
   collateral does not repay the trove automatically.

Footer links to Mezo and the explorer, plus “Built for Mezo Wave 1 · 2026”.

---

## 9. Cross-page behavior

- **Series selection is local.** The landing, trade, and secondary pages each read the
  factory and choose a series. The vault page always describes the vault's bound series.
- **Address watching is local.** The Trade and Secondary pages have independent viewers;
  connecting a wallet switches a viewer only when it is still on the deployer default.
- **Refresh.** Each transaction refreshes the data needed by the current page. The
  secondary page also has a manual refresh button.
- **Approvals.** The app reads the current allowance and submits an exact-amount approval
  only when it is insufficient. It does not request an unlimited approval.
- **Errors.** RPC reads that fail render an em dash or a fallback rather than a fabricated
  number. Transaction errors are shown as toast text.
- **No optimistic balances.** The UI waits for the transaction receipt before refreshing
  state.
- **No hidden writes.** Read-only mode never asks for a signature.

---

## 10. Data sources

| Data | Source |
| --- | --- |
| Chain | Mezo testnet `31611` |
| RPC | `https://rpc.test.mezo.org` |
| Series list | `RosterSeriesFactory.allSeries()` |
| Series state | `RosterBtcPutSeries` view functions |
| Token balances | MUSD and ERC-20 BTC `balanceOf` |
| BTC price | Mezo `PriceFeed.fetchPrice()` |
| Trove | `RosterTroveWriter.troveInfo()` |
| Vault buckets | `idleMUSD`, `reservedMUSD`, `premiumForwarded`, `expiryForwarded` |
| Listings | `RosterOrderBook.nextListingId` / `getListing` |
| Activity | `eth_getLogs` from the deployment block, in 9,000-block windows |
| Transactions | Injected wallet `eth_sendTransaction` |
| Explorer links | `https://explorer.test.mezo.org` |

The app reads through the public RPC even when a wallet is connected. Transaction
submission goes through the wallet's provider. There is no custom backend.

---

## 11. Browser evidence

### 11.1 Method

On **2026-10-26**, between approximately **01:15 and 01:25 UTC**, the production build
was served locally at `http://127.0.0.1:4173` and loaded in headless Chrome against the
live Mezo RPC. The session used:

- desktop viewport 1440 × 1000;
- mobile emulation 390 × 844;
- no wallet extension;
- no account connection;
- no transaction signature or broadcast.

This is a **read-only smoke test**, not a wallet integration test. **It predates the
position wrapper and Mezo Pools work.** The series values below (`75` lots, `1,498 MUSD`
collateral, `0.000025` vault BTC) are historical; the current state is `74` lots,
`1,497.92 MUSD`, and `0.000026` vault BTC, plus the wrapper/pool record in
[`COMPOSABILITY.md`](COMPOSABILITY.md).

### 11.2 Results

| Check | Result |
| --- | --- |
| Five pages load | Pass |
| Uncaught app exceptions | None observed |
| Desktop overflow | No horizontal overflow on any page (`document.scrollWidth == clientWidth`) |
| Mobile overflow | No horizontal overflow on any page |
| Mobile navigation | Visible on all pages |
| Live data | Spot, collateral, premium, supply, capacity, ICR, debt, vault buckets, ask book, and activity rendered |
| Trade quote | 100 lots → `0.1 MUSD` premium, `8 MUSD` payout, `0.0001 BTC`, enabled buy button |
| Vault close note | Required repayment and an approximate `1,551.99 MUSD` shortfall, counting the vault owner's MUSD |
| Activity | 13 decoded events; 8 contract cards at the check block |

Observed live values at the check:

```text
BTC spot                 approximately 80,085 MUSD/BTC
Series collateral        1,498 MUSD
Premium paid             0.1 MUSD
Active lots              75
Capacity left            18,650 lots
Trove collateral         0.043 native BTC
Trove debt               approximately 2,202.035 MUSD
Trove ICR                approximately 156.4%
Idle vault MUSD          400 MUSD
Reserved vault MUSD      0 MUSD
Vault ERC-20 BTC         0.000025 BTC
Premium forwarded        0.1 MUSD
Open asks                1 listing, 25 lots at 0.002 MUSD/lot
Activity                 13 decoded events
```

Debt and ICR move continuously. Treat these as observations, not constants.

### 11.3 Screenshots

Desktop:

- [`home-desktop.png`](screenshots/home-desktop.png)
- [`home-full.png`](screenshots/home-full.png) — full landing page
- [`trade-desktop.png`](screenshots/trade-desktop.png)
- [`secondary-desktop.png`](screenshots/secondary-desktop.png)
- [`vault-desktop.png`](screenshots/vault-desktop.png)
- [`activity-desktop.png`](screenshots/activity-desktop.png)

Mobile (390px emulation):

- [`home-mobile.png`](screenshots/home-mobile.png)
- [`trade-mobile.png`](screenshots/trade-mobile.png)
- [`secondary-mobile.png`](screenshots/secondary-mobile.png)
- [`vault-mobile.png`](screenshots/vault-mobile.png)
- [`activity-mobile.png`](screenshots/activity-mobile.png)

The screenshots were captured before the disclosure copy was changed from "two BTC
assets" to "two BTC accounting paths." The current source uses the corrected wording;
the screenshots are retained as historical evidence of the read-only pass.

### 11.4 Current production build

The browser-check build was `32.68 kB` for `index.html` and `18.71 kB` for `vault.html`.
The table below is the current source build after the disclosure-copy correction.

```text
dist/index.html                  32.82 kB │ gzip:  7.40 kB
dist/trade.html                  16.77 kB │ gzip:  4.29 kB
dist/secondary.html              14.60 kB │ gzip:  4.02 kB
dist/vault.html                  18.75 kB │ gzip:  4.80 kB
dist/activity.html               11.72 kB │ gzip:  3.41 kB
dist/assets/main-uU5dssex.css    42.88 kB │ gzip:  8.54 kB
dist/assets/main-3VKCUrVU.js    303.59 kB │ gzip: 109.60 kB
```

---

## 12. Build and run

```bash
cd app
npm ci
npm run dev
```

Production build:

```bash
npm run build
npm run preview
```

The build output is static. There is no server-side component. Public addresses are safe
to commit; private keys are never part of the app.

---

## 13. What the app does not include

- No series-creation UI.
- No writer deposit UI outside the owner console (deposit is a contract call).
- No trove open/add-collateral/borrow/repay UI (only close status and finalize).
- No position-token transfer UI outside listing.
- No allowance-revocation UI.
- No native-BTC wallet balance display.
- No bids, matching engine, order types, or partial-fill input.
- No premium auction or price discovery.
- No KYC, accounts, database, analytics, or backend.
- No notifications beyond in-page toasts.
- No dark/light theme switch.
- No explicit wallet disconnect button.
- No automated end-to-end browser test suite.
- No hosted production demo.
- No wallet transaction walkthrough or transaction screenshots.
- No position-wrapper UI and no Mezo Pools wrapper/MUSD pool UI. The app does not show
  wrapper balances, pool reserves, or a post-expiry wrapper warning.

---

## 14. Known gaps

- No wallet transaction has been performed through the UI.
- No wallet signature, pending, confirmation, or failure state has been recorded.
- No automated app tests.
- No hosted deployment.
- Activity timestamps depend on block metadata reads; the feed is not indexed.
- Premium-paid stat depends on event-log availability.
- Partial fills are not exposed in the UI even though the contract supports them.
- The app cannot close the live trove because the account is short MUSD.
- The app cannot finalize the main series before its 2026-11-24 expiry.
- The app does not convert native BTC to ERC-20 BTC.
- The app does not surface the position wrapper or the Mezo Pools wrapper/MUSD pool.
  Wrapper lots are not visible in the position viewer, and the app gives no pre-expiry
  unwind warning for wrapper holders.
- The browser pass is a historical read-only check (`75` lots, `1,498 MUSD`); one lot was
  later exercised through the wrapper, so the live series is now `74` lots and
  `1,497.92 MUSD`. The UI reads live data and will show the current values when opened.

The accurate description is: **implemented, production-building, and read-only
browser-validated on five pages at desktop and mobile widths; not wallet-tested; does not
surface the wrapper or Mezo Pools pool.**
