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
product. It is a compact mechanism demonstration with five separable pieces:

1. **A permissionless series factory** that registers immutable series.
2. **A series contract** that holds MUSD collateral, issues one-token-per-lot
   positions, collects premium, pays exact strike amounts on exercise, and releases
   residual collateral at expiry.
3. **An escrowed secondary ask book** that lets position holders exit before expiry
   without a matching engine or custodian.
4. **A per-series trove vault** that opens a real Mezo trove with native BTC, borrows
   MUSD, and funds its bound series as writer.
5. **A standard ERC-20 position wrapper and a Mezo Pools market** that let actual series
   positions be held, transferred, and settled outside Roster. The wrapper holds lots 1:1
   at `1e18` units per lot; a live Mezo Pools volatile pool holds the wrapper against
   MUSD.

The main series is live on Mezo testnet with a **80,000 MUSD/BTC strike**, a
**0.001 MUSD per lot premium**, and a **0.000001 BTC lot size**. A generated demo buyer
purchased 100 lots, sold 25 through the order book, and exercised 25 by delivering
ERC-20 BTC for an exact 2 MUSD payout. A separate generated account then acquired wrapper
tokens through the Mezo Pools router and exercised one more lot, bringing cumulative
payouts to 2.08 MUSD and leaving 74 active lots. The writer vault opened a trove with
**0.043 native BTC**, borrowed MUSD, and deposited **1,500 MUSD** into the series.

A second, short-dated series was deployed solely to exercise the expiry path. It has
now expired and released **20 MUSD** of residual collateral to its EOA writer. Its ten
position tokens remain frozen in the buyer's wallet, which is the intended post-expiry
behavior: the tokens are worthless after collateral release.

The project deliberately records what is missing as clearly as what is delivered. A
testnet deployment is not a security review, a customer base, or a promise of
liquidity. The wrapper/MUSD pool is deployer-seeded and thin, not organic liquidity.

---

## 2. What was delivered

| Deliverable | Status | Evidence |
| --- | --- | --- |
| `RosterBtcPutSeries` | Delivered | 36 unit tests; live main and demo series |
| `RosterSeriesFactory` | Delivered | 4 unit tests; live factory with two series |
| `RosterOrderBook` | Delivered | 13 unit tests; live listing and fill |
| `RosterTroveWriter` | Delivered | 23 unit tests; live trove and series funding |
| `RosterPositionWrapper` | Delivered | 9 unit tests; live wrapper over main-series lots |
| Mezo Pools wrapper/MUSD pool | Delivered, deployer-seeded | Live volatile pool through Mezo Pools; 15 lots / 0.03 MUSD seed |
| External position composability | Delivered | Generated external account swapped MUSD for wrapper and exercised 1 lot |
| Mezo testnet deployment | Delivered | [Deployment record](DEPLOYMENT_RECORD.md) |
| Live primary purchase | Delivered | 100 lots purchased by a separate buyer |
| Live secondary trade | Delivered | 50 lots listed, 25 filled |
| Live physical exercise | Delivered | 26 lots exercised for 2.08 MUSD total |
| Live premium withdrawal | Delivered | 0.1 MUSD forwarded through the vault |
| Live expiry path | Delivered on demo series | 20 MUSD released, tokens frozen |
| Web interface | Implemented, five-page production build passes | Read-only browser pass at desktop and mobile widths; no wallet transaction; does not surface wrapper/pool |
| Automated tests | 91/91 default and 91/91 CI | [Test output](TEST_OUTPUT.txt) |
| Repository consistency checks | Pass | `scripts/static_validate.py`; GitHub Actions workflow configured |
| Audit | **Not delivered** | Do not claim otherwise |
| Organic demand | **Not delivered** | Buyer and external account are generated demo accounts; pool is deployer-seeded |
| Trove closure | **Not demonstrated** | Current MUSD shortfall |
| Main-series expiry/finalization | **Not reached** | Expiry 2026-11-24 |
| MEZO governance-token integration | **Not delivered** | MUSD, Mezo credit, and Mezo Pools only |

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
5. **Mezo Pools is the external venue.** A wrapper/MUSD volatile pool was created through
   the Mezo Pools Basic PoolFactory and traded through the Basic Router. That is what makes
   the composability demonstration an external integration rather than a Roster-only
   wrapper.

What is **not** integrated:

- No MEZO governance-token staking, voting, rewards, or fee capture.
- No stability-pool participation.
- No liquidation or redemption bot.
- No Mezo bridge logic.
- No keeper network.
- No premium auction or market-based premium discovery.
- The app does not surface the wrapper or Mezo Pools pool.

If a rubric requires MEZO-token usage specifically, this submission does **not**
satisfy that requirement. It does use Mezo credit infrastructure, Mezo assets, and a
Mezo Pools venue.

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
- native BTC trove collateral and liquid ERC-20 BTC exercise proceeds are separate
  accounting buckets; trove collateral is locked.

### 4.8 Position wrapper and Mezo Pools pool

The series token has `decimals() == 0` and protocol-specific transfer restrictions.
`RosterPositionWrapper` is a separate, unowned adapter:

- `deposit(lots)` pulls series lots and mints `lots * 1e18` wrapper units;
- `withdraw(wrapperAmount)` burns whole-lot multiples and returns series lots;
- `exercise(wrapperAmount)` burns whole-lot multiples, pulls `lots * 1e12` ERC-20 BTC
  from the caller, calls `series.exercise(lots)`, and forwards the MUSD payout.

`UNIT = 1e18`. The wrapper holds series positions 1:1 and does not mint series positions,
change terms, or create leverage. It is **not** collateral for the trove, is **not**
redeemable for series collateral or native BTC, and has no owner, pause, upgrade, fee, or
rescue function. `deposit`, `withdraw`, and `exercise` are blocked after series expiry;
wrapper transfers remain open but wrapper tokens are worthless after expiry. Fractional
wrapper balances can be transferred but not settled. Series tokens sent directly to the
wrapper are uncredited.

A live Mezo Pools volatile pool at
`0xED305fEF4c11f95dAe1d144e78B2B62be50965F2` holds wrapper tokens against MUSD. It is a
third-party AMM, not a Roster market. It was seeded with 15 actual lots and 0.03 MUSD by
the deployer. The AMM cannot call `wrapper.exercise()`; pool-held lots must be sold to an
address that can deliver ERC-20 BTC and exercise before expiry.

---

## 5. Native BTC vs ERC-20 BTC

This distinction is about where BTC sits, not two independently issued BTC tokens:

| Accounting path | Where it lives | What it does |
| --- | --- | --- |
| **Native BTC trove collateral** | Mezo trove, `msg.value` | Locked collateral for the MUSD borrow. Not spendable exercise inventory. |
| **ERC-20 BTC** | `0x7b7C000000000000000000000000000000000000` | Mezo's ERC-20 interface to liquid BTC, delivered on exercise. Not a claim on trove collateral. |

The vault can receive native BTC from Mezo's `ActivePool` or `CollSurplusPool` when
collateral is withdrawn, a trove is closed, or surplus is claimed. It receives liquid
BTC only when a holder exercises. It exposes separate functions:

- `withdrawCollateral()` / `closeTrove()` / `claimCollateral()` — native BTC collateral
  paths;
- `withdrawBtc(to, amount)` — liquid BTC exercise proceeds.

Roster **does not convert locked trove collateral into exercise inventory** and does not
use trove collateral to settle exercises. It does not promise that the two accounting
buckets are interchangeable. A buyer needs liquid BTC to exercise. The writer is blocked
from exercising.

The wrapper does not change this. It holds series position tokens, not trove collateral
and not the series MUSD collateral. It gives an external venue a transferable ERC-20
claim that can be exercised, not a claim on the trove's BTC.

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
| `RosterPositionWrapper` | `0x4726a021ec380a755EBE883BEb800A5d06723E41` |
| Mezo Pools Basic PoolFactory | `0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A` |
| Mezo Pools Basic Router | `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9` |
| Wrapper/MUSD pool | `0xED305fEF4c11f95dAe1d144e78B2B62be50965F2` |
| Mezo MUSD/BTC pool (context) | `0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9` |

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
| Generated external pool buyer | `0x1Ed24CD690076B70381bEeb2Ce0D3d7F7625Ee3C` |

The buyer and external-account keys were generated for the demonstration. The external
account had no direct series position; it was funded by the deployer so it could acquire
wrapper tokens through the Mezo Pools router. It is a functional demonstration account,
not an independent customer. No private key or `.env` file is committed to the repository.

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
| Current collateral | `1,497.92 MUSD` after 26 lots exercised |
| Current active lots | `74` |
| Current reserve | `5.92 MUSD` |
| Current excess | `1,492 MUSD` |
| Cumulative payouts | `2.08 MUSD` |

### 6.5 Trove

| Parameter | Value at snapshot |
| --- | --- |
| Native BTC collateral | `0.043 BTC` |
| Trove debt | `2,202.057203102504956752 MUSD` |
| ICR | `1.568564521549903788` — **156.856%** |
| Mezo BTC price | `80,327.18147 MUSD/BTC` |
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
| Deployer funds buyer with 0.001 native gas BTC | `0x430568bca841c1f3cb0514b888831dbadc614256672cc2d4ab16b8a56db6007a` |
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

### 7.4 Wrapper, Mezo Pools, and external settlement

The wrapper and pool were added after the original lifecycle. All transactions returned
status `1`; the full ledger is in [`COMPOSABILITY.md`](COMPOSABILITY.md).

| Step | Transaction |
| --- | --- |
| Deploy wrapper | `0xe6e4b8c60ac5c8cd2c6f03ed541c82a5af8af42e0f45e1c3b272a956b5b297e7` |
| Approve and deposit 10 lots | `0x4d2cf5c3eff0f19deb0d5f714f06a30dc4d9e32901502f8cd63019dde0608741`, `0x596fcecc54e2de075eb84efcb0a3f478d0e484344bde89878a8dc849e8087728` |
| Create Mezo Pools pool | `0xa5ef82750d15bfb89e2db3cd99e2f65c4c044131fbfce8a1c00aba99f470c3d8` |
| Add 5 lots + 0.01 MUSD | `0xcd453d9521f628f10b3c508a903754fcf06c3f05e30800d06a9b8413d0d39e6d` |
| Deposit 10 more lots; add 10 + 0.02 MUSD | `0x9da7db90d7496b5c948840a2fbdf4a9d4f8c6c523733ae59301bf53f4b153bc3`, `0xc971c780d6bdb91f81988faf81f662eaeb075b0bdfa9e7277bfedbd39da26bcd` |
| External account swaps 0.00215 MUSD for wrapper | `0xf996972556c8c11a49bf2a3857c38631dc69a313e584d97636bb424fa10e5cd1` |
| External account exercises 1 lot | `0xf9376c6eafd76fbaeb96b1536814fad60c84e9f888b9aecae2af6c5e7fd4bab7` |

The external account received `1.002735998536819336` wrapper units, burned `1e18` through
`exercise()`, delivered `0.000001` ERC-20 BTC, and received `0.08` MUSD. The series moved
from 75 to 74 active lots, collateral from 1,498 to 1,497.92 MUSD, and cumulative payouts
from 2 to 2.08 MUSD. The wrapper ended at `19` lots and `19e18` supply, still 1:1 backed.
The pool ended with `13.997264001463180664` wrapper lots and `0.03214914` MUSD.

### 7.5 What the evidence proves

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
- position tokens remain frozen after expiry;
- a standard wrapper can hold actual series lots 1:1 and settle them through the series;
- a Mezo Pools pool can hold and transfer the wrapper against MUSD;
- a generated external account with no direct series position can acquire wrapper
  exposure through the Mezo router and exercise one lot.

They do **not** prove that the protocol is safe, that demand exists, that the trove can
be closed with current balances, that the main series can be finalized before its
maturity, that native BTC and ERC-20 BTC are convertible, or that the wrapper pool is
deep, organic, or able to exercise its own positions.

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

### 8.4 Wrapper invariants

```text
wrapper.totalSupply()    = wrapper.underlyingLots() * 1e18
wrapper.underlyingLots() = series lots deposited through deposit()
```

`deposit()` increments `underlyingLots` and mints `lots * 1e18`; `withdraw()` and
`exercise()` decrement both by a whole-lot amount. `exercise()` also burns the
corresponding series position. Direct series-token transfers to the wrapper are not
credited and can make the wrapper's token balance exceed `underlyingLots`; there is no
rescue path.

### 8.5 Token assumptions

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
- Wrapper uses `nonReentrant`, exact-balance checks, and whole-lot validation.
- Wrapper `exercise()` forwards the exact MUSD received from the series.
- Wrapper has no owner, pause, upgrade, fee, or rescue function.

### 9.2 Known risks and limitations

- **No audit.** No independent security review or formal verification, including the
  wrapper and Mezo Pools integration.
- **No organic demand.** The buyer and external account are generated accounts.
- **No premium discovery.** The writer sets a fixed premium.
- **Trove liquidation risk.** 0.043 native BTC backs 2,202.06 MUSD of debt at 156.856%
  ICR. A BTC price fall or debt rise can push the trove toward the 110% MCR.
- **Trove close is blocked.** Current MUSD is insufficient to repay the debt.
- **Series reserve is not trove collateral.** The 1,497.92 MUSD in the series does not
  automatically repay the trove, and the wrapper cannot repay it either.
- **No main expiry yet.** Main series matures 2026-11-24.
- **No keeper.** Expiry is lazy and manual; holders must exercise themselves.
- **Order-book escrow risk.** Lots listed at expiry cannot be recovered.
- **Direct transfers are stranded.** Unsolicited MUSD/BTC is not credited and has no
  rescue path; direct series-token transfers to the wrapper are also uncredited.
- **Writer restriction is not Sybil resistance.** A writer-controlled alternate address
  can buy and exercise.
- **Locked trove collateral is not convertible through Roster.**
- **Wrapper/pool risk.** The pool is deployer-seeded and thin; the deployer holds
  essentially all LP supply and can remove it. The AMM cannot exercise; pool-held lots
  must be sold before expiry. The wrapper cannot settle after expiry, and fractional
  balances cannot be withdrawn or exercised.
- **App not wallet-tested.** The five-page production build passes and a read-only
  browser pass at desktop/mobile widths is recorded with screenshots, but no wallet
  transaction has been sent through the UI and there is no automated E2E suite. The app
  does not surface the wrapper or pool.

---

## 10. Test evidence

```bash
forge fmt --check          # exit 0
forge build                # succeeds; lint warnings only
forge test -vvv            # 91 passed, 0 failed
FOUNDRY_PROFILE=ci forge test   # 91 passed, 0 failed
```

| Suite | Tests |
| --- | --- |
| `RosterSeriesFactoryTest` | 4 |
| `RosterTroveWriterTest` | 23 |
| `RosterBtcPutSeriesTest` | 36 |
| `RosterOrderBookTest` | 13 |
| `RosterPositionWrapperTest` | 9 |
| `SeriesInvariantTest` | 6 invariants |
| **Total** | **91** |

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
- no local fork test of Mezo Pools or the live wrapper/MUSD pool; the composability path
  was demonstrated on testnet, not reproduced in Foundry;
- the wrapper tests use local mocks and do not exercise adversarial AMM callbacks;
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
was connected and no transaction was signed or broadcast through the UI. **That pass
predates the wrapper and Mezo Pools work**, so its observed `75` active lots and
`1,498 MUSD` collateral are historical, not current.

The app is read-only without a wallet. It reads the public Mezo RPC directly; there is
no backend, database, account system, custody, or analytics service. Mezo's public RPC
caps `eth_getLogs` at 10,000 blocks, so the activity feed scans in 9,000-block windows.
The app does **not** currently surface the position wrapper or the Mezo Pools pool; that
integration is verified through `cast` and the explorer.

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

cast call 0x4726a021ec380a755EBE883BEb800A5d06723E41 \
  "totalSupply()(uint256)" --rpc-url "$RPC"
cast call 0x4726a021ec380a755EBE883BEb800A5d06723E41 \
  "underlyingLots()(uint256)" --rpc-url "$RPC"
cast call 0xED305fEF4c11f95dAe1d144e78B2B62be50965F2 \
  "getReserves()(uint256,uint256,uint256)" --rpc-url "$RPC"
cast call 0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A \
  "isPool(address)(bool)" 0xED305fEF4c11f95dAe1d144e78B2B62be50965F2 --rpc-url "$RPC"

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

1. Open the main series on the explorer and verify 74 active lots, 1,497.92 MUSD
   collateral, and the 80,000 MUSD strike.
2. Open the vault and verify the trove: 0.043 native BTC, ~2,202 MUSD debt, ~156.9% ICR.
3. Open the order book and verify listing `1`: 25 lots at 0.002 MUSD per lot, seller is
   the generated buyer.
4. Inspect the purchase, fill, exercise, and premium-withdrawal transactions.
5. Open the demo series and verify `expired = true`, zero collateral, and a 20 MUSD
   expiry release.
6. Open the wrapper and the wrapper/MUSD pool, and inspect the external swap and exercise
   transactions in [`COMPOSABILITY.md`](COMPOSABILITY.md).
7. Run the 91-test suite and the five-page app production build.
8. Inspect the read-only desktop and mobile screenshots in
   [`screenshots/`](screenshots/).
9. Read the limitations. Do not treat the demo buyer or the external account as demand.

What cannot be demonstrated today:

- closing the trove with current balances;
- main-series expiry or finalization;
- organic demand or premium discovery;
- deep, organic wrapper/MUSD liquidity, or independent demand for the wrapper;
- pool-side exercise of wrapper positions;
- wrapper settlement after expiry (the wrapper blocks it);
- a wallet transaction signed and broadcast through the app;
- an automated browser E2E suite or hosted app;
- an audit of Roster or the Mezo Pools integration.

---

## 14. Repository map

```text
src/
  RosterBtcPutSeries.sol     core series, position ledger, lifecycle
  RosterSeriesFactory.sol    permissionless series registry
  RosterOrderBook.sol        escrowed secondary asks
  RosterTroveWriter.sol      per-series Mezo trove vault
  RosterPositionWrapper.sol  18-decimal ERC-20 wrapper over series lots
  MockERC20.sol              local exact-transfer test token
  TestERC20Helpers.sol       adversarial callback/fee-on-transfer tokens
test/
  RosterBtcPutSeries.t.sol   36 core tests
  ProtocolExtensions.t.sol   40 factory/book/vault tests
  RosterPositionWrapper.t.sol 9 wrapper tests
  SeriesInvariant.t.sol      6 invariants
  TestBase.sol
script/
  DeploySeries.s.sol         standalone EOA-writer series
  DeployStack.s.sol          intended full-stack script
  CheckMezoAssets.s.sol      asset/protocol preflight
docs/
  SUBMISSION.md              this narrative
  COMPOSABILITY.md           wrapper, Mezo Pools, external-account evidence
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
- that the wrapper/MUSD pool is deep, organic, permanent, or a Roster market;
- that the wrapper is collateral, is redeemable for series collateral or native BTC, or
  can settle after expiry;
- that the pool can exercise its own positions;
- that the app supports the wrapper or Mezo Pools pool;
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
> secondary ask book, a wrapper/MUSD Mezo Pools market over actual series positions,
> verified issuance, purchase, fill, exercise, premium, expiry, and external settlement
> transactions, and a five-page app with read-only desktop/mobile browser evidence. It
> is not audited, has no organic demand, has not closed its trove, has not reached
> main-series maturity, has no organic wrapper liquidity, and has not had a wallet
> transaction performed through the UI.

Anything stronger than that is not supported by the current evidence.
