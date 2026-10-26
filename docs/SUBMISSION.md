# Roster: Fixed-Series BTC Puts on Mezo

**Wave 1 submission — live Mezo testnet demonstration**

> **Status:** working testnet mechanism, real Mezo MUSD, a real Mezo trove, a live
> secondary ask book, and verified lifecycle transactions. **No audit. No organic
> demand. No trove closure. No main-series expiry. The five-page web app builds and
> has a read-only desktop/mobile browser pass with screenshots, but no wallet
> transaction has been sent through the UI.**
>
> This document is current as of the snapshot in
> [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md). The root [`README.md`](../README.md)
> remains the canonical project record. Where this narrative and the on-chain state
> disagree, the chain and the README win.

---

## 1. Summary

Roster is a fixed-strike, fixed-expiry, physically settled BTC put mechanism built
for Mezo EVM. It is not a general options exchange and it is not an audited financial
product. It is a compact mechanism demonstration with four separable pieces:

1. **A permissionless series factory** that registers immutable series.
2. **A series contract** that holds MUSD collateral, issues one-token-per-lot
   positions, collects premium, pays exact strike amounts on exercise, and releases
   residual collateral at expiry.
3. **An escrowed secondary ask book** that lets position holders exit before expiry
   without a matching engine or custodian.
4. **A per-series trove vault** that opens a real Mezo trove with native BTC, borrows
   MUSD, and funds its bound series as writer.

The main series is live on Mezo testnet with a **80,000 MUSD/BTC strike**, a
**0.001 MUSD per lot premium**, and a **0.000001 BTC lot size**. A generated demo buyer
purchased 100 lots, sold 25 through the order book, and exercised 25 by delivering
ERC-20 BTC for an exact 2 MUSD payout. The writer vault opened a trove with
**0.043 native BTC**, borrowed MUSD, and deposited **1,500 MUSD** into the series.

A second, short-dated series was deployed solely to exercise the expiry path. It has
now expired and released **20 MUSD** of residual collateral to its EOA writer. Its ten
position tokens remain frozen in the buyer's wallet, which is the intended post-expiry
behavior: the tokens are worthless after collateral release.

The project deliberately records what is missing as clearly as what is delivered. A
testnet deployment is not a security review, a customer base, or a promise of
liquidity.

---

## 2. What was delivered

| Deliverable | Status | Evidence |
| --- | --- | --- |
| `RosterBtcPutSeries` | Delivered | 36 unit tests; live main and demo series |
| `RosterSeriesFactory` | Delivered | 4 unit tests; live factory with two series |
| `RosterOrderBook` | Delivered | 13 unit tests; live listing and fill |
| `RosterTroveWriter` | Delivered | 23 unit tests; live trove and series funding |
| Mezo testnet deployment | Delivered | [Deployment record](DEPLOYMENT_RECORD.md) |
| Live primary purchase | Delivered | 100 lots purchased by a separate buyer |
| Live secondary trade | Delivered | 50 lots listed, 25 filled |
| Live physical exercise | Delivered | 25 lots exercised for 2 MUSD |
| Live premium withdrawal | Delivered | 0.1 MUSD forwarded through the vault |
| Live expiry path | Delivered on demo series | 20 MUSD released, tokens frozen |
| Web interface | Implemented, five-page production build passes | Read-only browser pass at desktop and mobile widths; no wallet transaction |
| Automated tests | 82/82 default and 82/82 CI | [Test output](TEST_OUTPUT.txt) |
| Repository consistency checks | Pass | `scripts/static_validate.py`; GitHub Actions workflow configured |
| Audit | **Not delivered** | Do not claim otherwise |
| Organic demand | **Not delivered** | Buyer is a generated demo account |
| Trove closure | **Not demonstrated** | Current MUSD shortfall |
| Main-series expiry/finalization | **Not reached** | Expiry 2026-11-24 |
| MEZO governance-token integration | **Not delivered** | MUSD and Mezo credit only |

---

## 3. Why this is Mezo-specific

Roster is not a generic ERC-20 option with Mezo branding. Mezo assets and Mezo credit
infrastructure are load-bearing:

1. **MUSD is the quote, premium, and collateral asset.** Buyers pay premium in MUSD.
   The series reserve is MUSD. The vault borrows MUSD from Mezo.
2. **A real Mezo trove collateralizes the writer.** `RosterTroveWriter` calls
   `BorrowerOperations.openTrove`, `addColl`, `withdrawMUSD`, `repayMUSD`, and
   `closeTrove`, and reads `TroveManager` and `PriceFeed`.
3. **Mezo's ERC-20 BTC interface is the exercise asset.** A holder delivers
   `0x7b7C000000000000000000000000000000000000` to the writer and receives MUSD.
4. **Mezo's price feed is read live.** The vault checks BTC price and the trove ICR
   when opening and adjusting the trove.

What is **not** integrated:

- No MEZO governance-token staking, voting, rewards, or fee capture.
- No stability-pool participation.
- No liquidation or redemption bot.
- No Mezo bridge logic.
- No keeper network.
- No premium auction or market-based premium discovery.

If a rubric requires MEZO-token usage specifically, this submission does **not**
satisfy that requirement. It does use Mezo credit infrastructure and Mezo assets.

---

## 4. Mechanism

### 4.1 Series terms

A series is immutable at deployment:

- writer address;
- MUSD address;
- ERC-20 BTC address;
- strike `K_raw` in MUSD per BTC, 18 decimals;
- premium per lot in MUSD, 18 decimals;
- absolute Unix expiry;
- name and symbol.

The strike must be divisible by `1_000_000`, so the per-lot strike is an exact integer.
One position token represents one `1e-6 BTC` lot. The token ledger is implemented
inside the series contract and exposes an ERC-20-shaped interface with
`decimals() == 0`.

### 4.2 Primary purchase

A buyer calls `purchase(lots)` before maturity. The series:

1. rejects the writer as buyer;
2. computes `premium = lots × premium_per_lot_raw`;
3. computes `reserveNeeded = lots × strike_per_lot_raw`;
4. requires enough unreserved `excess_raw`;
5. pulls exact MUSD premium from the buyer;
6. mints one position token per lot.

Premium is non-refundable. Purchases freeze at maturity.

### 4.3 Exercise

A holder calls `exercise(lots)` before maturity. The series:

1. rejects the writer;
2. burns the position tokens;
3. pulls `lots × 1e12` ERC-20 BTC from the holder and sends it directly to the writer;
4. pays `lots × strike_per_lot_raw` MUSD from the series reserve to the holder.

Exercise is manual. There is no settlement oracle, no auto-exercise, and no net
settlement. The holder decides whether exercise is economically attractive. If the
holder does nothing before maturity, the position expires worthless and the writer
recovers the remaining collateral through `expire()`.

### 4.4 Maturity and expiry

At `block.timestamp >= expiry`:

- purchases revert;
- exercises revert;
- position transfers revert;
- `expire()` becomes callable by anyone;
- `expire()` releases remaining MUSD collateral to the writer and zeroes
  `active_lots`, `reserved_raw`, and `excess_raw`;
- position balances and `totalSupply()` remain frozen; the tokens are worthless;
- any unwithdrawn premium can still be withdrawn by the writer.

Finalization is lazy. Until someone calls `expire()`, collateral remains in the series
and the ledger reports the pre-expiry supply.

### 4.5 Premium

Premium is tracked separately from collateral:

```text
premium_balance_raw
```

Only the writer can call `withdrawPremium()`. Withdrawing premium does not reduce the
collateral reserve. For the trove-backed main series, the writer is the vault; the
vault pulls the series premium and forwards it to the vault owner.

### 4.6 Secondary ask book

The order book supports:

- `list(series, lots, pricePerLot)` — escrow position lots and publish an ask;
- `fill(listingId, lots)` — buy all or part of an ask with direct MUSD payment to the
  seller;
- `cancel(listingId)` — return remaining escrowed lots;
- `getListing(listingId)` — read the listing.

Restrictions:

- the series must be registered by the configured factory;
- the series MUSD must match the book MUSD;
- the series must be live;
- listings freeze at maturity and must be cancelled before expiry;
- escrowed lots cannot be exercised while listed;
- there are no bids, no matching engine, no fees, and no keeper incentives.

The book is a price-discovery aid, not a guarantee of liquidity. A seller who forgets
to cancel before maturity permanently loses the ability to recover the escrow.

### 4.7 Trove-backed writer

`RosterTroveWriter` is a separate vault per series:

1. Owner deploys the vault with Mezo protocol addresses, MUSD, ERC-20 BTC, and a
   minimum application ICR.
2. Owner creates a series through the factory with the vault as writer.
3. Owner calls `bindSeries(series)` once.
4. Owner calls `openAndFund(debtAmount, seriesDeposit, hints)` with native BTC:
   - opens a Mezo trove;
   - borrows MUSD;
   - approves the series;
   - deposits `seriesDeposit` MUSD into the series;
   - checks the post-operation ICR against `minICR`.
5. Owner can add collateral, borrow more, repay, deposit more into the series, withdraw
   idle MUSD, withdraw ERC-20 BTC exercise proceeds, and withdraw premium.
6. After series maturity, owner calls `finalize()`:
   - calls `series.expire()` if needed;
   - forwards the series expiry release to the owner exactly once;
   - withdraws and forwards remaining premium.
7. `closeTrove()` can repay the Mezo debt and return native BTC, but only if the owner
   can fund the repayment shortfall. The vault preserves any MUSD reserved for an
   already-released series expiry.

Important separation:

- the **series reserve** stays in the series contract;
- the **trove debt** is a Mezo obligation of the vault owner;
- the series reserve does **not** automatically repay the trove;
- closing the trove does **not** automatically close the series;
- native BTC collateral and ERC-20 BTC exercise proceeds are separate assets.

---

## 5. Native BTC vs ERC-20 BTC

This distinction is load-bearing:

| Asset | Where it lives | What it does |
| --- | --- | --- |
| **Native BTC** | Mezo trove, `msg.value` | Collateral for the MUSD borrow. Not the option settlement asset. |
| **ERC-20 BTC** | `0x7b7C000000000000000000000000000000000000` | Asset delivered on exercise. Not the trove collateral. |

The vault can receive native BTC from Mezo's `ActivePool` or `CollSurplusPool` when
collateral is withdrawn, a trove is closed, or surplus is claimed. It receives ERC-20
BTC only when a holder exercises. It exposes separate functions:

- `withdrawCollateral()` / `closeTrove()` / `claimCollateral()` — native BTC paths;
- `withdrawBtc(to, amount)` — ERC-20 BTC exercise proceeds.

Roster **does not convert** native BTC into ERC-20 BTC. It does not promise that the
two are interchangeable. A buyer needs ERC-20 BTC to exercise. The writer is blocked
from exercising.

---

## 6. Live deployment

All addresses are on **Mezo testnet, chain ID 31611**.

### 6.1 Contracts

| Role | Address |
| --- | --- |
| `RosterSeriesFactory` | `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F` |
| `RosterOrderBook` | `0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25` |
| `RosterTroveWriter` | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` |
| `RosterBtcPutSeries` (main) | `0xC23167867baAF830D586598DE0634E26fD895b92` |
| `RosterBtcPutSeries` (demo) | `0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43` |

### 6.2 Assets and Mezo protocol

| Role | Address |
| --- | --- |
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` |
| PriceFeed | `0x86bCF0841622a5dAC14A313a15f96A95421b9366` |
| BorrowerOperations | `0xCdF7028ceAB81fA0C6971208e83fa7872994beE5` |
| TroveManager | `0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0` |
| ActivePool | `0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51` |
| CollSurplusPool | `0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9` |

### 6.3 Accounts

| Role | Address |
| --- | --- |
| Deployer / vault owner | `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3` |
| Generated demo buyer | `0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5` |

The buyer key was generated for the demonstration. No private key or `.env` file is
committed to the repository.

### 6.4 Main series terms

| Parameter | Value |
| --- | --- |
| Name / symbol | `Roster Mezo BTC Put (Trove)` / `rBTC-PUT-T` |
| Writer | `RosterTroveWriter` at `0x214e…A331` |
| Strike | `80,000 MUSD/BTC` (`K_raw = 80000e18`) |
| Strike per lot | `0.08 MUSD` |
| Premium per lot | `0.001 MUSD` |
| Lot size | `0.000001 BTC` |
| Expiry | `1795519026` — 2026-11-24 11:17:06 UTC |
| Initial deposit | `1,500 MUSD` |
| Current collateral | `1,498 MUSD` after one exercise |
| Current active lots | `75` |
| Current reserve | `6 MUSD` |
| Current excess | `1,492 MUSD` |
| Cumulative payouts | `2 MUSD` |

### 6.5 Trove

| Parameter | Value at snapshot |
| --- | --- |
| Native BTC collateral | `0.043 BTC` |
| Trove debt | `2,202.001777260997830208 MUSD` |
| ICR | `1.569883623935996387` — **156.99%** |
| Mezo BTC price | `80,392.71 MUSD/BTC` |
| Trove status | `1` (active) |
| Application minimum ICR | `1.5e18` — 150% |
| Mezo liquidation MCR | 110% |
| MUSD gas compensation | `200 MUSD` |

Debt and interest move continuously. These are snapshot values, not constants.

---

## 7. Live lifecycle evidence

All transactions below have status `1` on Mezo testnet. Explorer path:
`https://explorer.test.mezo.org/tx/<hash>`.

### 7.1 Deployment and funding

| Step | Transaction |
| --- | --- |
| Deploy factory | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` |
| Deploy order book | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` |
| Deploy trove vault | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` |
| Create main series | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` |
| Bind vault to main series | `0x475ac4a22814c979e736d56644e74e51c26028c0a76edc24a7a6596461162929` |
| Open trove and fund series | `0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3` |

### 7.2 Main-series trading lifecycle

| Step | Transaction |
| --- | --- |
| Vault withdraws 100 idle MUSD | `0x42382fc32c88c42c7f16d8039f8bd7ea677d9575492ea1dc26d9b98fa3e122b1` |
| Deployer funds buyer with 50 MUSD | `0xfcdedbe4097ef8c5b874ec18535cca1fae9846b5c75419a3a84d0fbbf82c3e8c` |
| Deployer funds buyer with 0.001 ERC-20 BTC | `0x7955e79d23d2490e008a4ef92dcf95cdc4db63b8780bc987c3dd62f470f9e54a` |
| Buyer approves MUSD to series | `0x21a70bfcc088cfbae46bba0e1856b28527f7a8e044fb8c78223562e27f229a63` |
| Buyer purchases 100 lots (0.1 MUSD premium) | `0xe267876b92c517fd0f12f52b8f3935f683bdca6eda8b832c1837bc11e14c7186` |
| Buyer approves position tokens to book | `0x49fd70c707bfc9590cb0afb4d4665b4677b3f2ee5b99b7bad1f1889f5d20a169` |
| Buyer lists 50 lots at 0.002 MUSD/lot | `0x4c28017a4ca2f99c261b54ad30ecd4e21382b1e931eaae092fa76eda7ff3752e` |
| Deployer fills 25 lots (0.05 MUSD) | `0xd02d308ffd79ae818b78d88563189ffd9a3f88b72a13b0f93a73a4e1e5a2894e` |
| Buyer exercises 25 lots (0.000025 BTC → 2 MUSD) | `0x4230a5c81c8e351634306885098e5ad3765b27564c3d6ff08462815ce36f4991` |
| Vault withdraws 0.1 MUSD premium | `0x5f82341945dba350e179211cabb5031228844eebfb328acb9112bee715ce8a50` |

### 7.3 Demo expiry lifecycle

The demo uses the deployer EOA as writer, not the trove vault. It proves the series
expiry path, not the vault `finalize()` path.

| Step | Transaction |
| --- | --- |
| Create demo series | `0xa7ff146b3ce49b46a8de4582c3826b320797b28d1e70fff7669530b4a10cabae` |
| Approve 20 MUSD to demo series | `0x4280f849273e419d07533f3d205047f264422805b0f511e7289e883eb464f0c4` |
| Deposit 20 MUSD | `0x89c016b7f19d87e89dba2ae8c3ecc4a5081b15a87d5ea681a5e328bea4275946` |
| Buyer approves 0.01 MUSD | `0x5f52c73be0789064f6894bbbcea0d18df19113c77e665ba84141880a62487aa9` |
| Buyer purchases 10 lots | `0xafa7a0e6227dd3d2d5eca8cd16e072a9443331a8d5f86cdc4480b568c6ba3815` |
| Anyone calls `expire()` after maturity | `0xdc1b099d2f1a6256de62fdb28698167728416a9fb9df895ac19062d81eb5dd8d` |

After `expire()`:

- `expired = true`;
- `expiry_release_raw = 20 MUSD`;
- `collateral_balance_raw = 0`;
- `active_lots = 0`;
- `totalSupply()` remains `10` (frozen, worthless tokens);
- `premium_balance_raw = 0.01 MUSD` remains withdrawable by the EOA writer.

### 7.4 What the evidence proves

The live transactions prove that:

- the contracts compile and deploy on Mezo testnet;
- the factory creates series recognized by the order book;
- the vault opens a real Mezo trove, borrows MUSD, and funds the series;
- a separate buyer can approve and purchase position lots;
- a seller can escrow lots in the order book;
- a second account can fill an ask with MUSD;
- a holder can exercise by delivering ERC-20 BTC and receive the exact strike;
- the vault can withdraw premium;
- a series can expire and release residual collateral;
- position tokens remain frozen after expiry.

They do **not** prove that the protocol is safe, that demand exists, that the trove can
be closed with current balances, or that the main series can be finalized before its
maturity. They do not prove that native BTC and ERC-20 BTC are convertible.

---

## 8. Accounting and invariants

All external MUSD and BTC amounts are raw 18-decimal integers. The position token uses
`decimals() == 0` because one token is one lot.

### 8.1 Series arithmetic

```text
require(K_raw > 0 && K_raw % 1_000_000 == 0)
strike_per_lot_raw = K_raw / 1_000_000
lot_size_raw       = 1_000_000_000_000        # 1e-6 BTC
premium_raw        = lots * premium_per_lot_raw
strike_total_raw   = lots * strike_per_lot_raw
```

The strike divisibility rule makes every per-lot payout an exact integer. An 80,000
MUSD/BTC strike yields 0.08 MUSD per lot.

### 8.2 Series invariants at transaction boundaries

```text
collateral_balance_raw = reserved_raw + excess_raw
reserved_raw           = active_lots * strike_per_lot_raw
total_deposited_raw - total_payouts_raw - expiry_release_raw = collateral_balance_raw
```

Before maturity, including the limbo state after maturity but before `expire()`:

```text
totalSupply() = active_lots
```

After `expire()`:

```text
collateral_balance_raw = reserved_raw = excess_raw = active_lots = 0
_totalSupply remains equal to the frozen position balances
```

MUSD solvency after completed top-level operations:

```text
musd.balanceOf(series) >= collateral_balance_raw + premium_balance_raw
```

### 8.3 Vault invariants

```text
idleMUSD()     = MUSD balance - MUSD reserved for an already-released series expiry
reservedMUSD() = series.expiry_release_raw - expiryForwarded
```

`finalize()` is idempotent with respect to the expiry release. A third-party `expire()`
can send the release to the vault, and the owner can still forward it exactly once.
`closeTrove()` preserves the reserved amount when pulling the owner's repayment
shortfall.

### 8.4 Token assumptions

The contracts assume:

- MUSD and ERC-20 BTC are 18-decimal, exact-transfer ERC-20 tokens;
- `transfer` and `transferFrom` do not take fees or rebase balances;
- the series checks exact before/after balances and reverts on unexpected changes;
- the deployed token contracts are trusted; a `decimals()` check is not an audit.

---

## 9. Security posture

### 9.1 Controls present

- `nonReentrant` on lifecycle and position-moving functions.
- Exact before/after balance checks for MUSD and BTC movements.
- Checked multiplication for premium and reserve amounts.
- Writer-only deposits and premium withdrawal.
- Writer cannot purchase or exercise.
- Position transfers blocked to zero, writer, series, and at/after maturity.
- Capacity enforcement against `excess_raw`.
- Strike divisibility requirement.
- Token decimal checks in constructors.
- Vault ICR check after opening, borrowing, and collateral changes.
- Native BTC receiver restricted to Mezo's `ActivePool` and `CollSurplusPool`.
- Vault reserves already-released series proceeds during `closeTrove()`.
- Factory registration check in the order book.
- Immutable series terms; no owner, pause, upgrade, or rescue function.

### 9.2 Known risks and limitations

- **No audit.** No independent security review or formal verification.
- **No organic demand.** The buyer is a generated account.
- **No premium discovery.** The writer sets a fixed premium.
- **Trove liquidation risk.** 0.043 native BTC backs 2,202 MUSD of debt at 156.99%
  ICR. A BTC price fall or debt rise can push the trove toward the 110% MCR.
- **Trove close is blocked.** Current MUSD is insufficient to repay the debt.
- **Series reserve is not trove collateral.** The 1,498 MUSD in the series does not
  automatically repay the trove.
- **No main expiry yet.** Main series matures 2026-11-24.
- **No keeper.** Expiry is lazy and manual; holders must exercise themselves.
- **Order-book escrow risk.** Lots listed at expiry cannot be recovered.
- **Direct transfers are stranded.** Unsolicited MUSD/BTC is not credited and has no
  rescue path.
- **Writer restriction is not Sybil resistance.** A writer-controlled alternate address
  can buy and exercise.
- **Two BTC assets are not convertible through Roster.**
- **App not wallet-tested.** The five-page production build passes and a read-only
  browser pass at desktop/mobile widths is recorded with screenshots, but no wallet
  transaction has been sent through the UI and there is no automated E2E suite.

---

## 10. Test evidence

```bash
forge fmt --check          # exit 0
forge build                # succeeds; lint warnings only
forge test -vvv            # 82 passed, 0 failed
FOUNDRY_PROFILE=ci forge test   # 82 passed, 0 failed
```

| Suite | Tests |
| --- | --- |
| `RosterSeriesFactoryTest` | 4 |
| `RosterTroveWriterTest` | 23 |
| `RosterBtcPutSeriesTest` | 36 |
| `RosterOrderBookTest` | 13 |
| `SeriesInvariantTest` | 6 invariants |
| **Total** | **82** |

The CI profile uses 5,000 fuzz runs and 512 invariant runs at depth 100. The invariant
handler covers deposit, purchase, exercise, transfer, approval, `transferFrom`, premium
withdrawal, maturity, and finalization over a fixed actor set.

See [`TEST_PLAN.md`](TEST_PLAN.md) and [`TEST_OUTPUT.txt`](TEST_OUTPUT.txt).

### 10.1 What tests do not cover

- no independent audit or formal verification;
- no local fork simulation of Mezo's BTC token; its `decimals()` call fails under local
  Foundry/revm (`EvmError: NotActivated`), so live testnet transactions were used for the
  BTC path;
- no liquidation, redemption, or multi-block interest simulation against Mezo;
- no load, griefing, or economic-security analysis;
- no adversarial production token beyond local mocks.

---

## 11. Web application

The repository contains a static Vite + ethers **five-page** application under
[`app/`](../app/). The dedicated pages are:

| Page | Entry | Purpose |
| --- | --- | --- |
| Landing | `index.html` | Long-form mechanism, live ticket, risk, terms, and page directory |
| Trade | `trade.html` | Primary purchase, any-address position viewer, exercise |
| Secondary | `secondary.html` | List, browse, fill, and cancel escrowed asks |
| Vault | `vault.html` | Trove health, vault balances, owner console |
| Activity | `activity.html` | Decoded events, filters, contract directory |

Shared behavior includes:

- live series, vault, trove, price-feed, and order-book reads;
- wallet connection on chain 31611 with chain switch/add;
- purchase and exercise flows with exact approvals;
- ask listing, fill-all, and cancel flows;
- any-address position viewer;
- owner console for premium, idle MUSD, ERC-20 BTC, finalize, and close status;
- decoded on-chain activity feed with explorer links;
- contract directory with copy/explorer actions;
- explicit native-BTC vs ERC-20 BTC and trove-risk disclosures.

**Current status:** the five-page production build passes. On **2026-10-26**, between
approximately **01:15 and 01:25 UTC**, all five pages loaded live RPC data in headless
Chrome at 1440px and 390px emulation, with no app exceptions and no horizontal overflow.
Screenshots are in [`screenshots/`](screenshots/). The check was **read-only**: no wallet
was connected and no transaction was signed or broadcast through the UI.

The app is read-only without a wallet. It reads the public Mezo RPC directly; there is
no backend, database, account system, custody, or analytics service. Mezo's public RPC
caps `eth_getLogs` at 10,000 blocks, so the activity feed scans in 9,000-block windows.

Do not describe the app as finished, wallet-tested, transaction-tested, hosted, or fully
validated. The remaining app gap is wallet integration testing, not the read-only build.

---

## 12. How to verify

### 12.1 Read the chain

```bash
RPC=https://rpc.test.mezo.org

cast chain-id --rpc-url "$RPC"

cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "active_lots()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "collateral_balance_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "expired()(bool)" --rpc-url "$RPC"

cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "troveInfo()(uint256,uint256,uint256,uint256,uint8)" --rpc-url "$RPC"
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "idleMUSD()(uint256)" --rpc-url "$RPC"

cast call 0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25 \
  "getListing(uint256)((address,address,uint256,uint256,bool))" 1 --rpc-url "$RPC"

cast call 0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43 \
  "expired()(bool)" --rpc-url "$RPC"
cast call 0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43 \
  "expiry_release_raw()(uint256)" --rpc-url "$RPC"
```

### 12.2 Run the tests

```bash
forge fmt --check
forge build
forge test -vvv
FOUNDRY_PROFILE=ci forge test
```

### 12.3 Build the app

```bash
cd app
npm ci
npm run build
```

---

## 13. Demo flow

What a reviewer can inspect today:

1. Open the main series on the explorer and verify 75 active lots, 1,498 MUSD
   collateral, and the 80,000 MUSD strike.
2. Open the vault and verify the trove: 0.043 native BTC, ~2,202 MUSD debt, ~157% ICR.
3. Open the order book and verify listing `1`: 25 lots at 0.002 MUSD per lot, seller is
   the generated buyer.
4. Inspect the purchase, fill, exercise, and premium-withdrawal transactions.
5. Open the demo series and verify `expired = true`, zero collateral, and a 20 MUSD
   expiry release.
6. Run the 82-test suite and the five-page app production build.
7. Inspect the read-only desktop and mobile screenshots in
   [`screenshots/`](screenshots/).
8. Read the limitations. Do not treat the demo buyer as demand.

What cannot be demonstrated today:

- closing the trove with current balances;
- main-series expiry or finalization;
- organic demand or premium discovery;
- a wallet transaction signed and broadcast through the app;
- an automated browser E2E suite or hosted app;
- an audit.

---

## 14. Repository map

```text
src/
  RosterBtcPutSeries.sol     core series, position ledger, lifecycle
  RosterSeriesFactory.sol    permissionless series registry
  RosterOrderBook.sol        escrowed secondary asks
  RosterTroveWriter.sol      per-series Mezo trove vault
  MockERC20.sol              local exact-transfer/callback token
test/
  RosterBtcPutSeries.t.sol   36 core tests
  ProtocolExtensions.t.sol   40 factory/book/vault tests
  SeriesInvariant.t.sol      6 invariants
  TestBase.sol
script/
  DeploySeries.s.sol         standalone EOA-writer series
  DeployStack.s.sol          intended full-stack script
  CheckMezoAssets.s.sol      asset/protocol preflight
docs/
  SUBMISSION.md              this narrative
  VALIDATION_STATUS.md       validation and live-state status
  DEPLOYMENT_RECORD.md       addresses, hashes, terms, snapshots
  deployment.json            machine-readable deployment snapshot
  TEST_PLAN.md               test design and coverage
  TEST_OUTPUT.txt            recorded command output
  THREAT_MODEL.md            threat model and assumptions
  WEB_APP.md                 full multi-page web-app inventory
  screenshots/               read-only desktop and mobile evidence
app/                         five-page Vite + ethers web interface
README.md                    canonical project record
```

---

## 15. Limitations and non-claims

Do **not** claim any of the following:

- that Roster is audited, production-ready, or safe for real funds;
- that the trove has been closed, repaid, or proven profitable;
- that the main series has expired or been finalized;
- that there is organic customer demand;
- that the premium is market-discovered;
- that the order book guarantees liquidity;
- that native BTC and ERC-20 BTC are convertible through Roster;
- that the app is finished, wallet-tested, transaction-tested, hosted, or fully
  validated; a read-only browser pass with screenshots exists, but no wallet transaction
  has been sent through the UI;
- that the project uses the MEZO governance token;
- that Mezo's system-wide collateral ratio was checked during deployment;
- that an independent fork test executed Mezo liquidation, redemption, or close flows;
- that the demo series proves the main series' maturity flow — it exercises the same
  series code, but it is a separate EOA-writer deployment.

---

## 16. Strongest accurate description

> Roster is a working Mezo testnet mechanism with real MUSD, a real trove, a live
> secondary ask book, verified issuance, purchase, fill, exercise, premium, and expiry
> transactions, and a five-page app with read-only desktop/mobile browser evidence. It
> is not audited, has no organic demand, has not closed its trove, has not reached
> main-series maturity, and has not had a wallet transaction performed through the UI.

Anything stronger than that is not supported by the current evidence.
