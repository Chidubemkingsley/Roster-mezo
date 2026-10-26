# Roster — Fixed-Series BTC Puts on Mezo

> **Status: live Mezo testnet demonstration. Not audited. Not production-ready.**
>
> Roster is a fixed-strike, fixed-expiry, physically settled BTC put mechanism built for
> Mezo EVM. A trove-backed writer borrows MUSD against native BTC and funds a series.
> Buyers pay a fixed MUSD premium for position lots. A holder can exercise before
> maturity by delivering ERC-20 BTC and receiving the exact strike payout in MUSD.
> A secondary ask book allows holders to exit before expiry.

This README is the most complete description of the repository as of **2026-10-26**.
Where older documents disagree with this file, the on-chain state and the addresses and
transactions recorded here take precedence.

---

## Contents

1. [Status at a glance](#1-status-at-a-glance)
2. [What Roster does](#2-what-roster-does)
3. [Live deployment](#3-live-deployment)
4. [Main series terms and capacity](#4-main-series-terms-and-capacity)
5. [Mechanism](#5-mechanism)
6. [Native BTC vs ERC-20 BTC](#6-native-btc-vs-erc-20-btc)
7. [Accounting and invariants](#7-accounting-and-invariants)
8. [Live lifecycle evidence](#8-live-lifecycle-evidence)
9. [Live state snapshot](#9-live-state-snapshot)
10. [Trove debt, interest, and close status](#10-trove-debt-interest-and-close-status)
11. [Mezo integration](#11-mezo-integration)
12. [Build and test evidence](#12-build-and-test-evidence)
13. [Web interface](#13-web-interface)
14. [Repository layout](#14-repository-layout)
15. [Configuration](#15-configuration)
16. [Deployment guide](#16-deployment-guide)
17. [Verifying the live deployment](#17-verifying-the-live-deployment)
18. [Security model and limitations](#18-security-model-and-limitations)
19. [What is not claimed](#19-what-is-not-claimed)
20. [Roadmap](#20-roadmap)
21. [Documentation index](#21-documentation-index)
22. [License](#22-license)

---

## 1. Status at a glance

| Area | Status |
| --- | --- |
| Network | Mezo testnet, chain ID `31611` |
| Main series | `0xC23167867baAF830D586598DE0634E26fD895b92`, active |
| Series writer | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` (`RosterTroveWriter`) |
| Main expiry | `1795519026` — **2026-11-24 11:17:06 UTC** |
| Strike | **80,000 MUSD per BTC** (`K_raw = 80000e18`) |
| Premium | **0.001 MUSD per lot** (`1e15` raw) |
| Lot size | **0.000001 BTC** (`1e12` raw, 18-decimal ERC-20 BTC) |
| Series collateral | **1,498 MUSD** after one exercise; 75 active lots |
| Trove (snapshot 2026-10-25 12:11 UTC) | **0.043 native BTC**, debt **2,202.001777260997830208 MUSD**, ICR **156.99%** |
| Secondary book | `0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25`; listing 1 open |
| Factory | `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F` |
| Tests | **82/82** default profile; **82/82** CI profile |
| Short-dated demo series | `0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43`; expired 2026-10-25, 20 MUSD released, 10 tokens frozen |
| Audit | **None** |
| Organic demand | **None observed**; the buyer is a generated demo account |
| Trove closure | **Not demonstrated**; MUSD shortfall |
| Main expiry/finalize | **Not reached** |
| Web application | **Implemented; production build passes; five-page read-only browser pass**; no wallet transaction performed through the UI |
| Browser evidence | Read-only headless Chrome at 1440px and 390px emulation; no app exceptions or horizontal overflow; screenshots in [`docs/screenshots/`](docs/screenshots/) |
| Production readiness | **No** |

The project deliberately records both what works and what does not. A testnet deployment
is not a security review, a customer base, or a promise of liquidity.

---

## 2. What Roster does

Roster separates a BTC put into four independent pieces:

1. **A factory** registers permissionless, immutable series. Each series fixes its own
   strike, premium, expiry, name, and symbol.
2. **A series contract** holds MUSD collateral and issues position tokens. One position
   token is one `1e-6 BTC` lot with `decimals() == 0`. The token ledger is implemented
   inside the series contract and exposed through an ERC-20-shaped interface with
   protocol-specific transfer restrictions.
3. **A secondary ask book** lets a holder escrow position lots and sell them for MUSD.
   It is an ask-only book: no bids, no matching engine, no fees, no keeper.
4. **A per-series trove vault** opens a Mezo trove with native BTC, borrows MUSD, and
   deposits part of the borrowed MUSD into its bound series as writer collateral. The
   vault is a separate contract from the series and can only be bound to one series.

A buyer's economics are simple:

```text
pay:      lots × premium_per_lot_raw        (MUSD)
receive:  lots × 1e-6 BTC                   (on exercise, paid by the holder to the writer)
receive:  lots × strike_per_lot_raw         (MUSD, paid by the series on exercise)
```

Exercise is **manual**. The series does not auto-exercise at expiry, does not use a
settlement oracle, and does not net-settle. If the holder does nothing before maturity,
the position expires worthless and the writer recovers the remaining collateral through
`expire()`.

---

## 3. Live deployment

All addresses below are on **Mezo testnet, chain ID 31611**.

### 3.1 Contracts

| Role | Address | Notes |
| --- | --- | --- |
| `RosterSeriesFactory` | `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F` | Permissionless series registry |
| `RosterOrderBook` | `0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25` | Escrowed secondary asks |
| `RosterTroveWriter` | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` | Trove-backed writer for the main series |
| `RosterBtcPutSeries` (main) | `0xC23167867baAF830D586598DE0634E26fD895b92` | Active 30-day series |
| `RosterBtcPutSeries` (demo) | `0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43` | Expired short-dated demonstration; EOA writer; 20 MUSD released |
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` | Mezo testnet MUSD, 18 decimals |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` | Mezo-side BTC ERC-20 interface, 18 decimals |
| Mezo PriceFeed | `0x86bCF0841622a5dAC14A313a15f96A95421b9366` | `fetchPrice()` returns MUSD/BTC with 18 decimals |
| BorrowerOperations | `0xCdF7028ceAB81fA0C6971208e83fa7872994beE5` | Used by the trove vault |
| TroveManager | `0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0` | Used by the trove vault |
| ActivePool | `0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51` | Native BTC collateral pool |
| CollSurplusPool | `0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9` | Collateral surplus recovery |

Explorer base: `https://explorer.test.mezo.org`

### 3.2 Accounts used in the demonstration

| Role | Address |
| --- | --- |
| Deployer / vault owner | `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3` |
| Generated demo buyer | `0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5` |

The buyer key was generated for the demo and is kept outside the repository. No private
key or `.env` file is committed.

### 3.3 Deployment transactions

| Step | Transaction |
| --- | --- |
| Deploy factory | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` |
| Deploy order book | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` |
| Deploy trove vault | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` |
| Create main series | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` |
| Bind vault to series | `0x475ac4a22814c979e736d56644e74e51c26028c0a76edc24a7a6596461162929` |
| Open trove and fund series | `0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3` |

---

## 4. Main series terms and capacity

The main series is `0xC23167867baAF830D586598DE0634E26fD895b92`.

| Parameter | Value |
| --- | --- |
| Name / symbol | `Roster Mezo BTC Put (Trove)` / `rBTC-PUT-T` |
| Writer | `RosterTroveWriter` at `0x214e…A331` |
| MUSD | `0x1189…c503` |
| ERC-20 BTC | `0x7b7C…0000` |
| `K_raw` | `80000000000000000000000` (80,000 MUSD/BTC) |
| `strike_per_lot_raw` | `80000000000000000` (0.08 MUSD per lot) |
| `premium_per_lot_raw` | `1000000000000000` (0.001 MUSD per lot) |
| `LOT_SIZE_RAW` | `1000000000000` (0.000001 BTC) |
| Expiry | `1795519026` — 2026-11-24 11:17:06 UTC |
| Initial writer deposit | 1,500 MUSD |
| Current collateral | 1,498 MUSD |
| Current active lots | 75 |
| Current reserve | 6 MUSD |
| Current excess | 1,492 MUSD |
| Cumulative payouts | 2 MUSD |
| Premium balance | 0 MUSD (withdrawn to the vault/owner) |

### Capacity math

```text
one lot                 = 0.000001 BTC
strike per lot          = 80,000 / 1,000,000 = 0.08 MUSD
initial deposit         = 1,500 MUSD
maximum lots            = 1,500 / 0.08 = 18,750 lots
maximum BTC notional    = 1,500 / 80,000 = 0.01875 BTC
```

After 25 lots were exercised, the series paid out `2 MUSD` and retained `1,498 MUSD`.
The remaining capacity is `1,492 / 0.08 = 18,650 lots` (plus the 75 active lots already
reserved). This is a small-capacity testnet demonstration, not a deep market.

---

## 5. Mechanism

### 5.1 Primary purchase

A buyer calls:

```solidity
purchase(uint256 lots)
```

The series:

1. Requires the series to be live (`block.timestamp < expiry` and not expired).
2. Rejects the writer as a buyer.
3. Computes `premium = lots × premium_per_lot_raw`.
4. Computes `reserveNeeded = lots × strike_per_lot_raw`.
5. Requires enough unreserved `excess_raw` to cover the new reserve.
6. Moves MUSD premium from the buyer to the series.
7. Mints `lots` position tokens to the buyer.

Premium is non-refundable. Purchases freeze at maturity. The writer cannot buy its own
series, and position tokens cannot be transferred to the writer.

### 5.2 Exercise

A holder calls:

```solidity
exercise(uint256 lots)
```

The series:

1. Requires the series to be live and the caller to hold enough position tokens.
2. Rejects the writer.
3. Requires the holder to hold and approve the exact ERC-20 BTC amount:
   `lots × 1e12`.
4. Burns the position tokens.
5. Transfers the ERC-20 BTC from the holder directly to the writer.
6. Transfers the exact strike payout in MUSD from the series to the holder.

There is no oracle check at exercise. The holder decides whether exercise is economically
attractive; the contract only enforces the fixed strike and physical delivery.

### 5.3 Maturity and expiry

At `block.timestamp >= expiry`:

- `purchase()` reverts.
- `exercise()` reverts.
- Position transfers revert.
- `expire()` becomes callable by **anyone**.
- `expire()` sets `expired = true`, releases all remaining MUSD collateral to the writer,
  and sets `active_lots`, `reserved_raw`, and `excess_raw` to zero.
- Position token balances and `totalSupply()` remain unchanged; the tokens are frozen and
  worthless.
- The writer can still call `withdrawPremium()` for any premium not yet withdrawn.

The series uses lazy finalization: nobody has to call `expire()` at the exact maturity
second, but until it is called the collateral remains in the series and the token ledger
still reports the pre-expiry supply.

### 5.4 Premium

Premium is tracked separately from collateral:

```text
premium_balance_raw
```

Only the writer can call `withdrawPremium()`. Withdrawing premium does not reduce the
collateral reserve. For the trove-backed series, the writer is the vault; the vault's
`withdrawPremium()` pulls the series premium and forwards it to the vault owner.

### 5.5 Secondary ask book

The order book at `0xc97B…cd25` supports:

- `list(series, lots, pricePerLot)` — escrow position lots and publish an ask.
- `fill(listingId, lots)` — buy all or part of an ask; MUSD goes directly from the buyer
  to the seller.
- `cancel(listingId)` — seller returns the remaining escrowed lots.
- `getListing(listingId)` — read the listing.

Restrictions:

- The series must be registered by the configured factory.
- The series MUSD must match the book's MUSD.
- The series must be live (not expired and before maturity).
- Listings freeze at maturity; they must be cancelled before expiry.
- Escrowed lots cannot be exercised while listed.
- There are no bids, matching engine, fees, or keeper incentives.

The book is a price-discovery aid, not a guarantee of liquidity.

### 5.6 Trove-backed writer

`RosterTroveWriter` is a separate vault per series. Its lifecycle:

1. Owner deploys the vault with Mezo protocol addresses, MUSD, ERC-20 BTC, and a minimum
   application ICR.
2. Owner deploys a series through the factory with the vault as writer.
3. Owner calls `bindSeries(series)` once.
4. Owner calls `openAndFund(debtAmount, seriesDeposit, hints)` with native BTC:
   - opens a Mezo trove,
   - borrows `debtAmount` MUSD,
   - approves the series,
   - deposits `seriesDeposit` MUSD into the series,
   - checks the post-operation ICR against `minICR`.
5. Owner can add collateral, borrow more, repay, deposit more into the series, withdraw
   idle MUSD, withdraw ERC-20 BTC exercise proceeds, and withdraw premium.
6. After series maturity, owner calls `finalize()`:
   - calls `series.expire()` if needed,
   - forwards the series expiry release to the owner exactly once,
   - withdraws and forwards any remaining premium.
7. `closeTrove()` can repay the Mezo debt and return native BTC, but only if the owner can
   fund the repayment shortfall. The vault preserves any MUSD reserved for an already
   released series expiry.

Important separation:

- The **series reserve** stays in the series contract, not in the vault.
- The **trove debt** is a Mezo obligation of the vault owner.
- The series reserve does **not** automatically repay the trove.
- Closing the trove does **not** automatically close the series.
- Native BTC collateral and ERC-20 BTC exercise proceeds are separate assets.

---

## 6. Native BTC vs ERC-20 BTC

This distinction is load-bearing and is easy to misread:

| Asset | Where it lives | What it does |
| --- | --- | --- |
| **Native BTC** | Mezo trove, `msg.value` | Collateral for the MUSD borrow. It is not the option's settlement asset. |
| **ERC-20 BTC** | `0x7b7C000000000000000000000000000000000000` | The asset a holder delivers on exercise. It is not the trove collateral. |

The vault can receive native BTC from Mezo's `ActivePool` or `CollSurplusPool` when
collateral is withdrawn, a trove is closed, or surplus is claimed. It receives ERC-20 BTC
only when a holder exercises. It exposes separate functions:

- `withdrawCollateral()` / `closeTrove()` / `claimCollateral()` — native BTC paths.
- `withdrawBtc(to, amount)` — ERC-20 BTC exercise proceeds.

Roster **does not convert** native BTC into ERC-20 BTC, and does not promise that the two
are interchangeable. A writer needs ERC-20 BTC only if it wants to exercise its own
position; the writer is blocked from exercising. A buyer needs ERC-20 BTC to exercise.

The ERC-20 asset at `0x7b7C…0000` is not native BTC. This repository calls it
**ERC-20 BTC** and makes no claim that it is the same asset as native BTC or Ethereum
tBTC. Roster has no conversion path between the two.

---

## 7. Accounting and invariants

All external MUSD and BTC amounts are raw 18-decimal integers. The position token uses
`decimals() == 0` because one token is one lot.

### 7.1 Series arithmetic

```text
require(K_raw > 0 && K_raw % 1_000_000 == 0)
strike_per_lot_raw = K_raw / 1_000_000
lot_size_raw       = 1_000_000_000_000        # 1e-6 BTC
premium_raw        = lots * premium_per_lot_raw
strike_total_raw   = lots * strike_per_lot_raw
```

The strike divisibility rule makes every per-lot payout an exact integer. A strike of
80,000 MUSD/BTC yields 0.08 MUSD per lot.

### 7.2 Series invariants at transaction boundaries

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

### 7.3 Vault invariants

The vault tracks:

```text
idleMUSD()      = MUSD balance - MUSD reserved for an already-released series expiry
reservedMUSD()  = series.expiry_release_raw - expiryForwarded
```

`finalize()` is idempotent with respect to the expiry release: a third-party `expire()`
can send the release to the vault, and the owner can still forward it exactly once.
`closeTrove()` preserves the reserved amount when pulling the owner's repayment shortfall.

### 7.4 Token assumptions

The contracts assume:

- MUSD and ERC-20 BTC are 18-decimal, exact-transfer ERC-20 tokens.
- `transfer` and `transferFrom` do not take fees or rebase balances.
- The series checks exact before/after balances and reverts on unexpected changes.
- The deployed token contracts are trusted; a `decimals()` check is not a security audit.

---

## 8. Live lifecycle evidence

All transactions below succeeded on Mezo testnet. The explorer transaction path is
`https://explorer.test.mezo.org/tx/<hash>`.

### 8.1 Main series

| Step | Transaction / result |
| --- | --- |
| Deploy factory | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` |
| Deploy order book | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` |
| Deploy trove vault | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` |
| Create main series | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` |
| Bind vault to series | `0x475ac4a22814c979e736d56644e74e51c26028c0a76edc24a7a6596461162929` |
| Open trove and deposit 1,500 MUSD into series | `0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3` |
| Withdraw 100 MUSD idle from vault | `0x42382fc32c88c42c7f16d8039f8bd7ea677d9575492ea1dc26d9b98fa3e122b1` |
| Fund buyer with 50 MUSD | `0xfcdedbe4097ef8c5b874ec18535cca1fae9846b5c75419a3a84d0fbbf82c3e8c` |
| Fund buyer with 0.001 ERC-20 BTC | `0x7955e79d23d2490e008a4ef92dcf95cdc4db63b8780bc987c3dd62f470f9e54a` |
| Buyer approves MUSD to series | `0x21a70bfcc088cfbae46bba0e1856b28527f7a8e044fb8c78223562e27f229a63` |
| Buyer purchases 100 lots (0.1 MUSD premium) | `0xe267876b92c517fd0f12f52b8f3935f683bdca6eda8b832c1837bc11e14c7186` |
| Buyer approves position tokens to book | `0x49fd70c707bfc9590cb0afb4d4665b4677b3f2ee5b99b7bad1f1889f5d20a169` |
| Buyer lists 50 lots at 0.002 MUSD/lot | `0x4c28017a4ca2f99c261b54ad30ecd4e21382b1e931eaae092fa76eda7ff3752e` |
| Deployer fills 25 lots (0.05 MUSD) | `0xd02d308ffd79ae818b78d88563189ffd9a3f88b72a13b0f93a73a4e1e5a2894e` |
| Buyer exercises 25 lots (0.000025 BTC → 2 MUSD) | `0x4230a5c81c8e351634306885098e5ad3765b27564c3d6ff08462815ce36f4991` |
| Vault withdraws 0.1 MUSD premium | `0x5f82341945dba350e179211cabb5031228844eebfb328acb9112bee715ce8a50` |

### 8.2 Short-dated demo series

The demo series exists to demonstrate the expiry path without waiting for the main
series' 2026-11-24 maturity. It uses the deployer EOA as writer, not the trove vault.

| Step | Transaction / result |
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

### 8.3 What the evidence proves

The live transactions prove that:

- The contracts compile and deploy on Mezo testnet.
- The factory creates a series that is recognized by the order book.
- The vault opens a real Mezo trove, borrows MUSD, and funds the series.
- A separate buyer can approve and purchase position lots.
- A seller can escrow lots in the order book.
- A second account can fill an ask with MUSD.
- A holder can exercise by delivering ERC-20 BTC and receive exact MUSD.
- The writer/vault can withdraw premium.
- A series can expire, release residual collateral, and leave position tokens frozen.

They do **not** prove that the protocol is safe, that demand exists, that the trove can be
closed with current balances, that the main series can be finalized before its maturity,
or that native BTC and ERC-20 BTC are convertible through Roster.

---

## 9. Live state snapshot

Snapshot taken on **2026-10-25** at approximately **12:11 UTC**, block
**16,359,943**. Values move with interest, trades, and exercises.

### 9.1 Main series

| Field | Value |
| --- | --- |
| `active_lots` | `75` |
| `totalSupply()` | `75` |
| `collateral_balance_raw` | `1498e18` |
| `reserved_raw` | `6e18` |
| `excess_raw` | `1492e18` |
| `total_deposited_raw` | `1500e18` |
| `total_payouts_raw` | `2e18` |
| `expiry_release_raw` | `0` |
| `premium_balance_raw` | `0` |
| `expired` | `false` |
| Position holders | Buyer `25`, deployer `25`, order book escrow `25` |

### 9.2 Demo series

| Field | Value |
| --- | --- |
| `active_lots` | `0` |
| `totalSupply()` | `10` (frozen) |
| `collateral_balance_raw` | `0` |
| `expiry_release_raw` | `20e18` |
| `premium_balance_raw` | `0.01e18` |
| `expired` | `true` |
| `expiry` | `1792929664` — 2026-10-25 12:01:04 UTC |
| Writer | Deployer EOA, not the vault |

### 9.3 Order book

| Field | Value |
| --- | --- |
| `nextListingId` | `2` |
| Listing `1` seller | Buyer `0x1A1A…Dd3b5` |
| Listing `1` series | Main series |
| Listing `1` price | `0.002 MUSD` per lot |
| Listing `1` remaining | `25` lots |
| Listing `1` active | `true` |

The original 50-lot listing was partially filled: 25 lots were bought by the deployer and
25 remain escrowed.

### 9.4 Vault

| Field | Value |
| --- | --- |
| Vault MUSD balance | `400e18` |
| `idleMUSD()` | `400e18` |
| `reservedMUSD()` | `0` |
| ERC-20 BTC held | `0.000025 BTC` |
| `premiumForwarded()` | `0.1 MUSD` |
| `expiryForwarded()` | `0` |
| `totalDepositedToSeries()` | `1,500 MUSD` |
| Vault owner | Deployer `0x9035…9E3` |

### 9.5 Trove

| Field | Value |
| --- | --- |
| Native BTC collateral | `0.043 BTC` |
| Trove debt | `2,202.001777260997830208 MUSD` |
| Current ICR | `1.569883623935996387` — **156.99%** |
| Mezo BTC price | `80,392.71 MUSD/BTC` |
| Trove status | `1` (active) |
| Application minimum ICR | `1.5e18` — **150%** |
| Mezo liquidation MCR | **110%** |
| MUSD gas compensation | `200 MUSD` |

### 9.6 Account balances

| Account | MUSD | ERC-20 BTC |
| --- | --- | --- |
| Deployer / vault owner | `50.05 MUSD` | `0.004999993948523024 BTC` |
| Buyer | `51.94 MUSD` | `0.0019749992572 BTC` |

The deployer MUSD balance includes the 20 MUSD demo expiry release. Native BTC balances
are separate and are not shown in this table.

---

## 10. Trove debt, interest, and close status

The vault opened a trove with:

```text
requested borrow:        2,000 MUSD
borrowing fee:               2 MUSD (0.1% at deployment)
MUSD gas compensation:     200 MUSD
initial trove debt:      2,202 MUSD
```

The live debt had accrued a small amount of interest at the 12:11 UTC snapshot:

```text
debt at snapshot:        2,202.001777260997830208 MUSD
close repayment required = debt - 200 MUSD gas compensation
                         = 2,002.001777260997830208 MUSD
```

The vault holds `400 MUSD` idle. The owner holds `50.05 MUSD`, including the demo
expiry release. Available for repayment:

```text
400 + 50.05 = 450.05 MUSD
shortfall   = 2,002.001777260997830208 - 450.05
            = 1,551.951777260997830208 MUSD
```

The series holds `1,498 MUSD` of collateral, but **that MUSD belongs to the series reserve
and is not available to repay the trove**. Calling `closeTrove()` without the shortfall
would revert or would require additional MUSD from the owner.

No live DEX route was found for the missing MUSD on Mezo testnet. The documented pool
`0x52e604c44417233b6CcEDDDc0d640A405Caacefb` has no code at the time of writing. Therefore:

- **Trove closure is not demonstrated.**
- **Do not claim the trove can be closed profitably or at all with current balances.**
- Interest continues to accrue and changes the shortfall.
- A fall in BTC price or a rise in debt can reduce the ICR; at 156.99%, the buffer above
  the 110% Mezo MCR is about 47 percentage points, but this is not a guarantee.
- Liquidation would be a serious event for the vault owner; the series reserve accounting
  is separate, but the product does not make the owner whole.

The contract tests include the close-repayment path, including preservation of reserved
expiry proceeds. The live close is blocked by liquidity, not by missing code.

---

## 11. Mezo integration

Roster uses Mezo in four concrete ways:

1. **MUSD as premium and collateral.** Buyers pay premium in MUSD. The series reserve is
   MUSD. The vault borrows MUSD from Mezo.
2. **A real Mezo trove.** `RosterTroveWriter` calls `BorrowerOperations.openTrove`,
   `addColl`, `withdrawMUSD`, `repayMUSD`, `closeTrove`, and reads `TroveManager` and
   `PriceFeed`.
3. **Mezo's BTC ERC-20 interface.** The series uses
   `0x7b7C000000000000000000000000000000000000` as the exercise asset.
4. **Mezo's price feed.** The vault checks the live BTC price when opening and adjusting
   the trove.

What is **not** integrated:

- No MEZO governance-token usage, staking, voting, or rewards.
- No liquidation or redemption participation.
- No Mezo stability-pool integration.
- No keeper or automation network.
- No fee market or premium oracle.
- No cross-chain BTC bridge logic.

If a rubric requires MEZO-token usage specifically, this project does not satisfy that
requirement. It does use Mezo credit infrastructure and Mezo assets.

---

## 12. Build and test evidence

### 12.1 Toolchain

| Tool | Version / setting |
| --- | --- |
| Foundry | `1.7.1` |
| Solidity | `0.8.24` |
| EVM version | `london` |
| Optimizer | enabled, 200 runs |
| `via_ir` | `true` |
| Test dependency | no `forge-std`; local `Vm` interface only |

### 12.2 Commands and results

```bash
forge fmt --check          # exit 0
forge build                # succeeds; lint warnings only
forge test -vvv            # 82 passed, 0 failed
FOUNDRY_PROFILE=ci forge test   # 82 passed, 0 failed
python3 scripts/static_validate.py  # PASS
```

The same commands run in the GitHub Actions workflow at
[`.github/workflows/test.yml`](.github/workflows/test.yml). The static script checks
required files, relative Solidity imports, test-name and hardening expectations, sample
configuration, deployment preflight strings, and the documented strike arithmetic. It is
a consistency check, not a compiler or EVM test.

Test breakdown:

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

See [`docs/TEST_OUTPUT.txt`](docs/TEST_OUTPUT.txt) for the recorded run. It includes the
live deployment, the five-page app build, and the read-only browser checks, and no
longer carries the old "not yet performed" note.

### 12.3 Build warnings

`forge build` succeeds with lint warnings, primarily:

- `block.timestamp` comparisons in lifecycle checks;
- unchecked return values in test-only token calls.

These are warnings, not compiler errors. `forge fmt --check` is clean.

### 12.4 What the tests do not cover

- No independent audit or formal verification.
- No local fork simulation of Mezo's BTC token. Its `decimals()` call reverts under
  local Foundry/revm forks (`EvmError: NotActivated`) even though live `cast` calls and
  transactions succeed. Live testnet transactions were used for the BTC path.
- No liquidation, redemption, or multi-block interest simulation against Mezo.
- No adversarial token with rebasing or fee-on-transfer behavior beyond the local mocks.
- No load, griefing, or economic-security analysis.

---

## 13. Web interface

The repository contains a static Vite + ethers **multi-page** application under
[`app/`](app/). It is not a single-page app. Five separate HTML entries share one
page-aware module and one stylesheet:

```text
app/
├── index.html       # long-form landing page and live ticket
├── trade.html       # primary market: buy, position, exercise
├── secondary.html   # ask book: list, fill, cancel
├── vault.html       # trove health, vault balances, owner console
├── activity.html    # decoded event log and contract directory
├── package.json     # Vite + ethers
├── vite.config.js   # five Rollup inputs
└── src/
    ├── config.js    # live addresses, ABIs, chain config
    ├── main.js      # page-aware reads, wallet, actions, rendering
    └── styles.css   # visual system and responsive rules
```

### 13.1 Pages

| Page | Entry | What it contains |
| --- | --- | --- |
| Landing | `index.html` | Editorial explanation of the mechanism, live series ticket, stat strip, live terms, native-BTC vs ERC-20 BTC separation, trove risk, secondary-market explainer, lifecycle, page directory, verification guidance, and disclosures. It links to the functional pages rather than duplicating their controls. |
| Trade | `trade.html` | Series selector, live ticket, primary purchase quote and button, any-address position viewer, exercise quote and button, series facts, and payoff explanation. |
| Secondary | `secondary.html` | Live ask summary, series selector, list form, open-ask table with fill-all/cancel, compact position readout, and settlement rules. |
| Vault | `vault.html` | Trove health and ICR, debt and collateral, vault balance buckets, owner console for premium/idle MUSD/ERC-20 BTC/finalize/close status, accounting rules, and limits. |
| Activity | `activity.html` | Event summary, category filters, decoded on-chain log with explorer links, eight-card contract directory, and verification instructions. |

The shared shell provides the Roster brand, Trade/Secondary/Vault/Activity navigation,
the Mezo Testnet pill, wallet connect button, toast stack, and footer. The active page is
marked in the navigation. `main.js` selects its behavior from `body[data-page]`, so each
entry only loads the data it needs.

### 13.2 Shared behavior

- Reads the live Mezo testnet RPC directly; no backend, database, account system, or
  analytics service.
- Works read-only without a wallet. A wallet is needed only for transactions.
- Reads the factory registry and falls back to the known main and demo series if the
  registry call fails.
- Shows the selected series in the ticket: status, strike, premium, expiry, countdown,
  spot, active lots, remaining capacity, utilization, writer, and writer type.
- Provides purchase and exercise flows with exact MUSD or ERC-20 BTC allowances.
- Provides list, fill-all, and cancel flows through the shared order book.
- Provides an any-address position viewer; the default watched address is the deployer.
- Provides owner-only controls for premium, idle MUSD, ERC-20 BTC, `finalize()`, and
  `closeTrove()` status.
- Decodes activity from the factory, both series, the order book, and the vault. Mezo's
  public RPC caps `eth_getLogs` at a 10,000-block span, so the app scans in 9,000-block
  windows and keeps the feed working as the chain advances.
- Links every transaction and contract to `https://explorer.test.mezo.org`.
- Uses exact-amount approvals, not unlimited approvals.
- Discloses testnet status, native-BTC vs ERC-20 BTC separation, and trove liquidation
  risk in the interface.

A full inventory is in [`docs/WEB_APP.md`](docs/WEB_APP.md).

### 13.3 Read-only browser validation

On **2026-10-26**, between approximately **01:15 and 01:25 UTC**, the production build
was served locally and loaded in headless Chrome against the live Mezo RPC. This was a
read-only pass: no wallet extension was installed, no account was connected, and no
transaction was signed or broadcast through the UI.

| Check | Result |
| --- | --- |
| Five pages load | Pass: landing, trade, secondary, vault, activity |
| Uncaught app exceptions | None observed |
| Desktop layout | 1440px wide; `document.scrollWidth == clientWidth` on all five pages |
| Mobile layout | 390px emulation; navigation visible; `document.scrollWidth == clientWidth` on all five pages |
| Live reads | BTC spot, series collateral, premium paid, trove debt/ICR, vault buckets, ask book, activity log, and contract cards all rendered |
| Trade quote | 100 lots produced `0.1 MUSD` premium, `8 MUSD` strike payout, `0.0001 BTC` delivered, with an enabled buy button |
| Vault close status | Displayed required repayment and an approximate `1,551.99 MUSD` shortfall, counting the vault owner's MUSD |
| Activity log | 13 decoded events at the check block; the page also exposed all eight contract cards |

The live values move with interest and trading. At the browser check the observed state
included approximately `$80,085` spot, `1,498 MUSD` series collateral, `75` active lots,
`156.4%` trove ICR, one `25`-lot ask at `0.002 MUSD` per lot, and `400 MUSD` idle vault
MUSD. These are time-sensitive observations, not constants.

Screenshots:

- [Landing — desktop](docs/screenshots/home-desktop.png) and
  [full page](docs/screenshots/home-full.png)
- [Trade — desktop](docs/screenshots/trade-desktop.png)
- [Secondary — desktop](docs/screenshots/secondary-desktop.png)
- [Vault — desktop](docs/screenshots/vault-desktop.png)
- [Activity — desktop](docs/screenshots/activity-desktop.png)
- Mobile: [landing](docs/screenshots/home-mobile.png),
  [trade](docs/screenshots/trade-mobile.png),
  [secondary](docs/screenshots/secondary-mobile.png),
  [vault](docs/screenshots/vault-mobile.png),
  [activity](docs/screenshots/activity-mobile.png)

Production build at the final check:

```text
dist/index.html                  32.68 kB │ gzip:  7.39 kB
dist/trade.html                  16.77 kB │ gzip:  4.29 kB
dist/secondary.html              14.60 kB │ gzip:  4.02 kB
dist/vault.html                  18.71 kB │ gzip:  4.79 kB
dist/activity.html               11.72 kB │ gzip:  3.41 kB
dist/assets/main-uU5dssex.css    42.88 kB │ gzip:  8.54 kB
dist/assets/main-3VKCUrVU.js    303.59 kB │ gzip: 109.60 kB
```

The build output is recorded in [`docs/TEST_OUTPUT.txt`](docs/TEST_OUTPUT.txt).

### 13.4 What remains unvalidated

- No browser wallet was connected and no transaction was sent through the UI.
- No screenshot shows a wallet signature, pending transaction, confirmation, or error.
- No automated end-to-end browser test suite.
- No hosted production deployment.
- The app cannot close the live trove with current balances and cannot finalize the main
  series before its 2026-11-24 expiry.

The accurate description is: **implemented, production-building, and read-only
browser-validated on five pages at desktop and mobile widths; not wallet-tested.** Do not
describe it as a finished or fully validated end-user product.

---

## 14. Repository layout

```text
.
├── src/
│   ├── RosterBtcPutSeries.sol     # core series, position ledger, lifecycle
│   ├── RosterSeriesFactory.sol    # permissionless series registry
│   ├── RosterOrderBook.sol        # secondary escrowed asks
│   ├── RosterTroveWriter.sol      # per-series Mezo trove vault
│   └── MockERC20.sol              # local exact-transfer / callback token
├── test/
│   ├── RosterBtcPutSeries.t.sol   # 36 core unit tests
│   ├── ProtocolExtensions.t.sol   # 40 factory/book/vault tests
│   ├── SeriesInvariant.t.sol      # 6 invariants
│   └── TestBase.sol
├── script/
│   ├── DeploySeries.s.sol         # standalone EOA-writer series deployment
│   ├── DeployStack.s.sol          # intended full-stack deployment script
│   └── CheckMezoAssets.s.sol      # asset/protocol preflight
├── docs/
│   ├── SUBMISSION.md
│   ├── TEST_PLAN.md
│   ├── TEST_OUTPUT.txt
│   ├── THREAT_MODEL.md
│   ├── VALIDATION_STATUS.md
│   ├── DEPLOYMENT_RECORD.md
│   ├── WEB_APP.md
│   ├── deployment.json             # machine-readable deployment snapshot
│   └── screenshots/                # read-only desktop and mobile browser evidence
├── app/
│   ├── index.html                  # long-form landing page
│   ├── trade.html                  # primary market
│   ├── secondary.html              # secondary ask book
│   ├── vault.html                  # trove vault
│   ├── activity.html               # decoded events and contracts
│   ├── vite.config.js              # five-page build
│   └── src/                        # config, page-aware logic, styles
├── .env.example                    # template; never put a real key in git
├── .github/workflows/test.yml      # build, default/CI tests, fmt, static checks
├── scripts/static_validate.py      # repository consistency checks
├── foundry.toml
├── Makefile
└── README.md
```

`DeployStack.s.sol` documents the intended full-stack sequence, but it cannot be simulated
locally against Mezo's BTC token because its `decimals()` call reverts in a local
Foundry/revm fork (`EvmError: NotActivated`). The live stack was deployed in stages with
`forge create` and `cast send`, then verified on-chain. See §16.

---

## 15. Configuration

Copy `.env.example` to `.env`, fill in a real testnet key locally, and **never commit
`.env`**. The template is a template: the key, writer, and expiry must be replaced for a
new deployment.

Source it with exported variables:

```bash
set -a
. ./.env
set +a
```

Plain `source .env` does not export shell variables to child processes; Foundry's
`vm.envUint` and `vm.envAddress` read exported environment variables.

### 15.1 Variables

| Variable | Purpose | Notes |
| --- | --- | --- |
| `MEZO_TESTNET_RPC_URL` | Mezo testnet RPC | `https://rpc.test.mezo.org` |
| `MEZO_TESTNET_CHAIN_ID` | Expected chain | `31611` |
| `PRIVATE_KEY` | Broadcast key | Local only; never commit |
| `WRITER_ADDRESS` | EOA writer for `DeploySeries.s.sol` | Must equal the key's address; ignored by `DeployStack.s.sol` |
| `MUSD_ADDRESS` | Mezo MUSD | Verified 18 decimals |
| `BTC_ADDRESS` | Mezo ERC-20 BTC | Verified 18 decimals |
| `BORROWER_OPERATIONS_ADDRESS` | Mezo BorrowerOperations | Used by vault |
| `TROVE_MANAGER_ADDRESS` | Mezo TroveManager | Used by vault |
| `MEZO_PRICE_FEED_ADDRESS` | Mezo PriceFeed | Used by vault |
| `STRIKE_RAW` | MUSD per BTC, 18 decimals | Must be divisible by `1e6` |
| `PREMIUM_PER_LOT_RAW` | MUSD premium per lot | Must be nonzero |
| `EXPIRY` | Absolute Unix timestamp | Must be in the future |
| `SERIES_NAME` / `SERIES_SYMBOL` | Series metadata | Quote names containing spaces/parentheses |
| `TROVE_COLLATERAL_RAW` | Native BTC posted to Mezo | **Not** ERC-20 BTC |
| `TROVE_DEBT_RAW` | Requested MUSD borrow | Final debt adds fee + gas compensation |
| `SERIES_DEPOSIT_RAW` | MUSD deposited into series | Must be ≤ requested borrow |
| `MIN_ICR_RAW` | Application minimum ICR | Bounded by `1.2e18` to `5e18` |

### 15.2 Important configuration caveats

- `EXPIRY` is an **absolute** timestamp. Do not put a duration such as `3600` in it.
  Compute one with `date -d '+30 days' +%s` and replace the value.
- `WRITER_ADDRESS` is only for the standalone EOA-writer script. In the full-stack flow,
  the series writer is the newly deployed vault, not the deployer EOA.
- `TROVE_DEBT_RAW` is a **requested borrow**, not final debt. For a 2,000 MUSD borrow at
  the observed 0.1% fee, initial debt was 2,202 MUSD including the 200 MUSD gas
  compensation.
- The deployment preflight checks the individual trove ICR and the live price. It does
  **not** check Mezo's system-wide collateral ratio; leave a buffer.
- Native BTC collateral is not ERC-20 BTC. Do not assume convertibility.
- The short-dated demo series was deployed manually; there is no `DEMO_*` script in the
  current tree. The live demo addresses and transactions are recorded in §8.2.

---

## 16. Deployment guide

### 16.1 Preflight

```bash
set -a; . ./.env; set +a

cast chain-id --rpc-url "$MEZO_TESTNET_RPC_URL"
cast code "$MUSD_ADDRESS" --rpc-url "$MEZO_TESTNET_RPC_URL"
cast code "$BTC_ADDRESS" --rpc-url "$MEZO_TESTNET_RPC_URL"
cast call "$MUSD_ADDRESS" "decimals()(uint8)" --rpc-url "$MEZO_TESTNET_RPC_URL"
cast call "$BTC_ADDRESS" "decimals()(uint8)" --rpc-url "$MEZO_TESTNET_RPC_URL"

forge script script/CheckMezoAssets.s.sol:CheckMezoAssets \
  --rpc-url "$MEZO_TESTNET_RPC_URL" -vvvv
```

The preflight checks chain ID, token code, 18-decimal metadata, protocol contract code,
expiry, strike divisibility, requested debt, gas compensation, price, and ICR.

### 16.2 Standalone EOA-writer series

```bash
forge script script/DeploySeries.s.sol:DeploySeries \
  --rpc-url "$MEZO_TESTNET_RPC_URL" \
  --broadcast \
  -vvvv
```

This creates a series whose writer is the deploying EOA. It does **not** create a trove
vault, factory, or order book. The sample `.env.example` is oriented toward the full
stack, not this standalone path.

### 16.3 Full stack, staged

The intended one-shot script is `script/DeployStack.s.sol`, but local simulation against
Mezo's BTC token is blocked. The live deployment used this staged sequence:

1. Deploy `RosterSeriesFactory(musd, btc)`.
2. Deploy `RosterOrderBook(musd, factory)`.
3. Deploy `RosterTroveWriter(owner, borrowerOps, troveManager, priceFeed, musd, btc, minICR)`.
4. Call `factory.createSeries(vault, strike, premium, expiry, name, symbol)`.
5. Call `vault.bindSeries(series)`.
6. Call `vault.openAndFund{value: collateral}(requestedBorrow, seriesDeposit, hint, hint)`.
7. Verify the series, vault, and trove state with `cast call`.

Use `forge create --constructor-args-path` for constructor arguments, and `cast send`
for the calls. A robust broadcast pattern is `cast send --async`, then poll the receipt:
Mezo's RPC sometimes returns a null response after a transaction has already succeeded.

### 16.4 Post-deployment checks

```bash
# Factory
cast call "$FACTORY" "seriesCount()(uint256)" --rpc-url "$RPC"
cast call "$FACTORY" "seriesAt(uint256)(address)" 0 --rpc-url "$RPC"

# Series
cast call "$SERIES" "active_lots()(uint256)" --rpc-url "$RPC"
cast call "$SERIES" "collateral_balance_raw()(uint256)" --rpc-url "$RPC"
cast call "$SERIES" "reserved_raw()(uint256)" --rpc-url "$RPC"
cast call "$SERIES" "excess_raw()(uint256)" --rpc-url "$RPC"
cast call "$SERIES" "expired()(bool)" --rpc-url "$RPC"

# Vault and trove
cast call "$VAULT" "troveInfo()(uint256,uint256,uint256,uint256,uint8)" --rpc-url "$RPC"
cast call "$VAULT" "idleMUSD()(uint256)" --rpc-url "$RPC"
cast call "$VAULT" "reservedMUSD()(uint256)" --rpc-url "$RPC"

# Book
cast call "$BOOK" "nextListingId()(uint256)" --rpc-url "$RPC"
```

---

## 17. Verifying the live deployment

### 17.1 Explorer

- Factory: `https://explorer.test.mezo.org/address/0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F`
- Main series: `https://explorer.test.mezo.org/address/0xC23167867baAF830D586598DE0634E26fD895b92`
- Vault: `https://explorer.test.mezo.org/address/0x214e2316EAEeE24c1dc5d8433329fFC7544DA331`
- Order book: `https://explorer.test.mezo.org/address/0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25`
- Demo series: `https://explorer.test.mezo.org/address/0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43`

### 17.2 Key reads

```bash
RPC=https://rpc.test.mezo.org

# Main series state
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "active_lots()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "collateral_balance_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "premium_balance_raw()(uint256)" --rpc-url "$RPC"

# Trove
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "troveInfo()(uint256,uint256,uint256,uint256,uint8)" --rpc-url "$RPC"

# Secondary listing
cast call 0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25 \
  "getListing(uint256)((address,address,uint256,uint256,bool))" 1 --rpc-url "$RPC"
```

### 17.3 Reproducing the test suite

```bash
forge fmt --check
forge build
forge test -vvv
FOUNDRY_PROFILE=ci forge test
```

---

## 18. Security model and limitations

### 18.1 Trust assumptions

- MUSD and ERC-20 BTC are trusted, exact-transfer, 18-decimal tokens.
- Mezo's BorrowerOperations, TroveManager, PriceFeed, ActivePool, and CollSurplusPool are
  trusted protocol contracts.
- The vault owner is trusted to manage the trove and the series reserve.
- The factory has no owner or pause; anyone can create a series.
- The order book has no owner, pause, fee, or upgrade path.
- The series is immutable; its writer, assets, strike, premium, and expiry cannot change.

### 18.2 Protocol-specific restrictions

1. The writer cannot purchase, receive position tokens, or exercise. This is a demo
   policy, not Sybil resistance: a writer-controlled alternate address can still buy and
   exercise.
2. Position transfers are blocked to the zero address, the writer, the series itself, and
   at/after maturity. The token is not an unrestricted ERC-20.
3. `approve()` is intentionally unguarded; it changes allowance only. Position-moving and
   lifecycle functions share a reentrancy guard.
4. Direct MUSD/BTC transfers to the series are not credited as deposits and are not
   recoverable in Wave 1. There is no rescue function.
5. The collateral and solvency properties are transaction-boundary properties. During an
   external token callback, effects-first bookkeeping can temporarily lead the incoming
   asset balance.
6. Fee-on-transfer, rebasing, or malicious tokens are rejected by exact-balance checks
   where the code observes them, but the design assumes a trusted token.
7. Listing escrow means listed lots cannot be exercised until cancelled; a seller who
   forgets to cancel before maturity permanently loses the ability to recover the escrow.
8. The order book is ask-only and has no guarantee of a buyer.
9. The series does not auto-exercise, auto-settle, or protect against a holder forgetting
   to exercise.
10. The vault's trove can be liquidated independently of the series. The series reserve is
    accounted for separately but is not a guarantee of the owner's solvency.

### 18.3 Economic limitations

- One trove-backed writer and one active main series.
- One generated buyer; no organic demand.
- Fixed premium set by the writer; no auction or market-based premium discovery.
- Small capacity: 18,750 lots maximum at current deposit, 75 active.
- No market maker, keeper, or liquidity incentive.
- No buyback, fee, or governance token.
- No guarantee that secondary asks clear or that the writer can close the trove.

### 18.4 Operational limitations

- Testnet only.
- No audit or independent security review.
- No monitoring, alerting, or incident response.
- No upgrade path; contracts are immutable.
- No mainnet deployment.

---

## 19. What is not claimed

Do **not** claim any of the following:

- That Roster is audited, production-ready, or safe for real funds.
- That the trove has been closed, repaid, or proven profitable.
- That the main series has expired or been finalized.
- That there is organic customer demand.
- That the premium is market-discovered.
- That the order book guarantees liquidity.
- That native BTC and ERC-20 BTC are convertible through Roster.
- That the app is finished, wallet-tested, transaction-tested, hosted, or fully
  validated. A read-only five-page browser pass and screenshots exist, but no wallet was
  connected and no transaction was sent through the UI.
- That the project uses the MEZO governance token.
- That Mezo's system-wide collateral ratio was checked in the deployment script.
- That an independent fork test executed Mezo liquidation, redemption, or close flows.
- That the short-dated demo series proves the main series' maturity flow. It exercises
  the same series code, but it is a separate EOA-writer deployment.

---

## 20. Roadmap

Near-term, in order:

1. Connect an injected wallet, execute a live purchase or exercise through the UI, and
   record the signature, confirmation, and failure states. The read-only five-page
   browser pass, mobile layout check, and screenshots are already complete; wallet
   transaction testing is not.
2. Add an automated end-to-end browser test suite and a hosted demo.
3. Find or create a compliant MUSD source to close the trove, or explicitly leave it open
   and document the shortfall.
4. Add a formal threat-model review and independent audit before any real-fund use.
5. Wait for the main series to reach its 2026-11-24 expiry and demonstrate `expire()` /
   `finalize()` on the vault-bound series.
6. Add monitoring for trove ICR, debt, and main-series expiry.

Medium-term:

- Premium discovery (auctions, RFQs, or market-set premiums).
- Multiple independent writers and series.
- Liquidation and redemption monitoring.
- MEZO-token or Mezo governance integration, if required by the product.
- Keeper/automation for expiry and settlement.
- Better BTC acquisition and treasury management.
- Mainnet readiness review.

---

## 21. Documentation index

| Document | Purpose | Status |
| --- | --- | --- |
| [`README.md`](README.md) | Primary project, deployment, and evidence record | This file; current |
| [`docs/SUBMISSION.md`](docs/SUBMISSION.md) | Submission narrative | Current; matches the live deployment |
| [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md) | Test scenarios and invariants | Current; 82/82 pass |
| [`docs/TEST_OUTPUT.txt`](docs/TEST_OUTPUT.txt) | Recorded test/build/live/browser evidence | Current; includes multi-page app build and read-only browser checks |
| [`docs/VALIDATION_STATUS.md`](docs/VALIDATION_STATUS.md) | Validation and live-state summary | Current; includes read-only browser pass and remaining wallet gap |
| [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) | Threat model and assumptions | Current for the deployed design |
| [`docs/DEPLOYMENT_RECORD.md`](docs/DEPLOYMENT_RECORD.md) | Addresses, hashes, terms, snapshots | Current; live record |
| [`docs/deployment.json`](docs/deployment.json) | Machine-readable deployment state | Current snapshot plus app evidence |
| [`docs/WEB_APP.md`](docs/WEB_APP.md) | Full multi-page web-app inventory | Current; read-only browser pass recorded |
| [`docs/screenshots/`](docs/screenshots/) | Desktop and mobile browser screenshots | Read-only evidence; no wallet transaction |
| [`.env.example`](.env.example) | Configuration template | Replace key, writer, and expiry; never commit `.env` |
| [`app/`](app/) | Five-page Vite + ethers application | Implemented; build passes; read-only browser pass; wallet transaction not performed |

---

## 22. License

MIT. See [`LICENSE`](LICENSE).

---

### Final note

The strongest description of this repository is:

> A working testnet mechanism with real Mezo MUSD, a real trove, a live secondary book,
> verified lifecycle transactions, and a five-page app with read-only browser evidence —
> but no audit, no organic demand, no premium discovery, no trove closure, no main-series
> expiry, and no wallet transaction performed through the UI.

Anything stronger than that is not supported by the current evidence.
