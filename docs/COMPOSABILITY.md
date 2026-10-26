# External Composability Record — Mezo Pools

**Status:** live on Mezo testnet; demonstrated with a third-party account.
**Snapshot:** block `16,379,045`, 2026-10-26 10:15:56 UTC.
**Canonical project record:** [`../README.md`](../README.md).
**Related:** [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md),
[`VALIDATION_STATUS.md`](VALIDATION_STATUS.md), [`SUBMISSION.md`](SUBMISSION.md).

This document records the external-composability work added after the original
five-page app submission. It is deliberately narrow: it demonstrates one external
integration involving **actual Roster positions**, not a general money market, not a
deep options market, and not a claim of organic demand.

---

## 1. Why this exists

A wrapper alone is not composability. An MUSD/BTC swap alone is not Roster
composability. The useful test is whether an external protocol can hold, price, and
transfer a claim on a real Roster position, and whether a third party can acquire and
settle that claim.

The delivered path is:

```text
external buyer
    │  MUSD
    ▼
Mezo Pools Basic Router  ──►  vAMM-MUSD/wRBTC-PUT pool
                                  │  holds wrapper tokens
                                  ▼
                         RosterPositionWrapper
                                  │  holds 1:1 series position lots
                                  ▼
                         RosterBtcPutSeries (main)
                                  │  exercise: ERC-20 BTC in, MUSD out
                                  ▼
                         RosterTroveWriter (writer)
```

The pool is a real Mezo Pools volatile pool. The wrapper is a standard 18-decimal
ERC-20 adapter over the series' zero-decimal position token. The external buyer used
the Mezo router, received wrapper tokens from the pool, and exercised one lot through
the wrapper.

---

## 2. Contracts and addresses

All addresses are on **Mezo testnet, chain ID `31611`**.

| Role | Address | Notes |
| --- | --- | --- |
| `RosterPositionWrapper` | `0x4726a021ec380a755EBE883BEb800A5d06723E41` | 18 decimals; `1e18 = 1` series lot |
| Wrapped series | `0xC23167867baAF830D586598DE0634E26fD895b92` | Main series |
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` | 18 decimals |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` | 18 decimals; exercise asset |
| Mezo Pools Basic PoolFactory | `0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A` | Permissionless pool factory |
| Mezo Pools Basic Router | `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9` | Add/remove liquidity and swaps |
| Wrapper/MUSD pool | `0xED305fEF4c11f95dAe1d144e78B2B62be50965F2` | `vAMM-MUSD/wRBTC-PUT` |
| Mezo MUSD/BTC pool (context) | `0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9` | Existing Mezo pool; not used for the trove close |

The wrapper, pool factory, router, and pool are separate contracts. Roster does not own
or upgrade the Mezo Pools contracts, and this repository has not audited them.

Factory/pool checks:

```text
factory.getPool(wrapper, MUSD, false) = 0xED305fEF4c11f95dAe1d144e78B2B62be50965F2
factory.isPool(pool)                  = true
pool.token0()                         = MUSD
pool.token1()                         = wrapper
pool.stable()                         = false
pool.symbol()                         = "vAMM-MUSD/wRBTC-PUT"
factory.allPoolsLength()              = 38 at the snapshot
```

---

## 3. Wrapper semantics

`RosterPositionWrapper` is a conventional ERC-20 with these rules:

| Operation | Behavior |
| --- | --- |
| `deposit(lots)` | Pulls `lots` series position tokens (0-decimal) and mints `lots * 1e18` wrapper tokens. Requires series approval. |
| `withdraw(wrapperAmount)` | Burns a whole-lot multiple (`wrapperAmount % 1e18 == 0`) and returns the underlying lots. |
| `exercise(wrapperAmount)` | Burns a whole-lot multiple, pulls `lots * 1e12` ERC-20 BTC from the caller, calls `series.exercise(lots)`, and forwards the exact MUSD payout to the caller. |
| `transfer` / `transferFrom` | Standard ERC-20 movement of wrapper tokens, including to the Mezo pool. |
| `approve` | Standard allowance; zero spender is rejected. |
| `balanceOf` / `totalSupply` | 18-decimal wrapper units. |

Key properties:

- `UNIT = 1e18`; one wrapper token unit is one `1e-6 BTC` series lot.
- The wrapper custodies the series positions. It does not mint new series positions,
  change the series terms, or create leverage.
- The wrapper is **not** collateral for the trove and is **not** redeemable for series
  collateral or native BTC. The only settlement path is `exercise()` before expiry.
- `deposit`, `withdraw`, and `exercise` are blocked after series expiry. Wrapper
  transfers remain open so a pool or holder can unwind, but after expiry the wrapper
  cannot return or settle the underlying positions. Wrapper tokens are therefore
  worthless after expiry.
- Direct series-token transfers to the wrapper are not credited by `deposit()` and have
  no rescue path. Only the deposit path increases wrapper supply.
- A fractional wrapper balance (less than `1e18`) can be transferred but cannot be
  withdrawn or exercised.
- The wrapper has no owner, pause, upgrade, fee, or rescue function.

The full contract is [`../src/RosterPositionWrapper.sol`](../src/RosterPositionWrapper.sol).
The nine tests are in [`../test/RosterPositionWrapper.t.sol`](../test/RosterPositionWrapper.t.sol).

---

## 4. Pool seed and current state

The pool was created permissionlessly through the Mezo Pools Basic PoolFactory and
seeded by the deployer. It is not a Roster-owned pool and has no Roster liquidity
incentive.

Seed history:

| Step | Wrapper lots | MUSD | Implied price |
| --- | --- | --- | --- |
| Initial liquidity | 5 | 0.010 | 0.002 MUSD/lot |
| Additional liquidity | 10 | 0.020 | 0.002 MUSD/lot |
| **Total seeded** | **15** | **0.030** | **0.002 MUSD/lot** |

Current reserves after the external swap:

```text
MUSD reserve        = 0.032149140000000000
wrapper reserve     = 13.997264001463180664 e18
implied marginal    = 0.002296816006088 MUSD per lot
LP total supply     = 670.820393249936907
deployer LP balance = 670.820393249935907  (1000 wei locked)
```

The deployer holds all LP tokens (apart from the 1000 wei minimum-liquidity lock). This
is a **deployer-seeded test pool**, not evidence of external liquidity provision.
Price impact is large relative to the pool size; the external swap moved the marginal
price by roughly 15%.

---

## 5. External account demonstration

The external account is a fresh address generated for this demonstration:

```text
external address = 0x1Ed24CD690076B70381bEeb2Ce0D3d7F7625Ee3C
```

It had **no direct Roster series position** (`series.balanceOf(external) == 0`). It was
funded by the deployer with testnet MUSD, BTC for gas/settlement, and a small ERC-20 BTC
amount. The funding is disclosed because it means this is a functional demonstration,
not organic demand.

### 5.1 Before the swap

```text
external MUSD           = 0.010000000000000000
external ERC-20 BTC     = ~0.0003019999 (0.000302 funded, net of gas)
external wrapper        = 0
external series lots    = 0
```

### 5.2 Swap through Mezo Pools

The external account approved the router for `0.00215 MUSD` and called:

```solidity
swapExactTokensForTokens(
    0.00215e18,
    1.0e18,                         // minimum out
    [(MUSD, wrapper, false, factory)],
    external,
    deadline
)
```

The router quoted and paid:

```text
MUSD in        = 0.002150000000000000
wrapper out    = 1.002735998536819336
```

### 5.3 Exercise through the wrapper

The external account approved the wrapper for `1e12` ERC-20 BTC and called:

```solidity
wrapper.exercise(1e18)
```

Result:

```text
wrapper burned       = 1.000000000000000000
ERC-20 BTC delivered = 0.000001000000000000
MUSD payout          = 0.080000000000000000
```

### 5.4 After settlement

```text
external MUSD           = 0.087850000000000000
external ERC-20 BTC     = 0.000300999867586176
external wrapper        = 0.002735998536819336  (fractional dust)
external series lots    = 0
```

The external buyer paid `0.00215 MUSD` for the wrapper plus `0.000001 BTC` for exercise.
At the snapshot BTC price (`80,327.18147 MUSD/BTC`), the delivered BTC was worth about
`0.080327 MUSD`; the `0.08 MUSD` payout was therefore slightly below the BTC delivered,
before the wrapper cost. This was a **functional settlement demonstration, not a
profitable trade**.

### 5.5 State changes

```text
wrapper totalSupply      20.0 -> 19.0 e18
wrapper underlyingLots   20   -> 19
series active_lots       75   -> 74
series collateral        1,498.00 -> 1,497.92 MUSD
series reserved          6.00 -> 5.92 MUSD
series total payouts     2.00 -> 2.08 MUSD
pool wrapper reserve     15.0 -> 13.997264001463180664 e18
pool MUSD reserve        0.03 -> 0.03214914 e18
```

The wrapper's remaining 19 lots are backed 1:1:

```text
wrapper.totalSupply() / 1e18 = 19
wrapper.underlyingLots()     = 19
```

---

## 6. Transaction ledger

All transactions below returned receipt status `1`.

### 6.1 Wrapper deployment and first deposit

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Deploy `RosterPositionWrapper` | `0xe6e4b8c60ac5c8cd2c6f03ed541c82a5af8af42e0f45e1c3b272a956b5b297e7` | 16,378,802 | 1,348,146 |
| Approve series to wrapper | `0x4d2cf5c3eff0f19deb0d5f714f06a30dc4d9e32901502f8cd63019dde0608741` | 16,378,810 | 45,927 |
| Deposit 10 lots | `0x596fcecc54e2de075eb84efcb0a3f478d0e484344bde89878a8dc849e8087728` | 16,378,811 | 116,859 |

### 6.2 Pool creation and seed

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Create pool | `0xa5ef82750d15bfb89e2db3cd99e2f65c4c044131fbfce8a1c00aba99f470c3d8` | 16,378,881 | 708,845 |
| Approve MUSD to router | `0xfd4be100fa7ad7f0857d96639107e184b3729083bb12d20fd887bc72f2da0393` | 16,378,893 | 46,382 |
| Approve wrapper to router | `0x8a96714c29610cc9ec7886351542dcec177468c4fdfc1bc64f4e43f3c974b475` | 16,378,895 | 45,987 |
| Add 5 lots + 0.01 MUSD | `0xcd453d9521f628f10b3c508a903754fcf06c3f05e30800d06a9b8413d0d39e6d` | 16,378,904 | 325,475 |
| Approve 10 more series lots | `0xe6803824ed88d8911f41405994eb9e2f200552397b43bbb475a0e3a00ec80237` | 16,378,937 | 28,827 |
| Deposit 10 more lots | `0x9da7db90d7496b5c948840a2fbdf4a9d4f8c6c523733ae59301bf53f4b153bc3` | 16,378,940 | 65,559 |
| Approve 0.02 MUSD to router | `0xcddfbb6c95fcf6013dc8849d0ec48e4c3fa3b8a5027a3ed09f06a0b8a7298d32` | 16,378,949 | 46,382 |
| Approve 10 wrapper to router | `0x3eacf9e5dea3500f871e5ccae181e23b3889f3c4495afb0e2f4911d34ee78292` | 16,378,951 | 45,987 |
| Add 10 lots + 0.02 MUSD | `0xc971c780d6bdb91f81988faf81f662eaeb075b0bdfa9e7277bfedbd39da26bcd` | 16,378,953 | 197,863 |

### 6.3 External buyer funding, swap, and exercise

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Fund external with 0.0003 native gas BTC | `0xb6a3dfe9050927c35a276d40954777d2c3ca27ac18bc76f5d94324b1ae01e410` | 16,378,963 | 21,000 |
| Fund external with 0.01 MUSD | `0x401cf6dbcd2c83a59d788fdc4f7f5802358ef3185a87f5ab98fb82ff5ee6ddbb` | 16,378,965 | 51,673 |
| Fund external with 0.000002 ERC-20 BTC | `0x551ecebe47cfb624348f88601244193d44b6ea11b64d888fb64696a92c2a09f1` | 16,378,967 | 25,540 |
| External approves MUSD to router | `0x19773260376a1746d039f0899d6ddb35eaaa602286405a8b15e817531350ac0f` | 16,378,978 | 46,394 |
| External swaps 0.00215 MUSD for wrapper | `0xf996972556c8c11a49bf2a3857c38631dc69a313e584d97636bb424fa10e5cd1` | 16,378,984 | 231,293 |
| External approves ERC-20 BTC to wrapper | `0x0cef19d51580d817ccecd24304b1fe3190966560a0b3bf9daac098dacf83bee7` | 16,378,989 | 25,528 |
| External exercises 1 lot | `0xf9376c6eafd76fbaeb96b1536814fad60c84e9f888b9aecae2af6c5e7fd4bab7` | 16,378,991 | 150,257 |

Explorer path: `https://explorer.test.mezo.org/tx/<hash>`.

---

## 7. What this proves

- A Mezo Pools volatile pool can hold a standard ERC-20 wrapper backed 1:1 by actual
  Roster series positions.
- The Mezo Pools factory recognizes the wrapper/MUSD pool (`isPool == true`,
  `getPool(...) == pool`).
- A third-party account with no direct Roster position can acquire wrapper exposure
  through the Mezo router and AMM.
- The wrapper's approval, `transferFrom`, `exercise`, and MUSD-forwarding paths work
  against live Mezo MUSD and ERC-20 BTC.
- The series' exercise accounting stayed consistent: 1 lot burned, 1e-6 BTC delivered,
  0.08 MUSD paid, active lots and reserve reduced by one lot.
- The wrapper stayed 1:1 backed after the exercise (`totalSupply == underlyingLots`).

## 8. What this does not prove

- **Organic demand.** The external buyer was funded by the deployer. It is a generated
  demo account, not a customer.
- **Deep liquidity or fair pricing.** The pool holds 15 lots and 0.03 MUSD of
  deployer-seeded liquidity. It is a testnet demonstration, not a market.
- **That LPs can exercise.** The pool cannot call `wrapper.exercise()`. Pool-held
  wrapper lots must be sold to an address that can exercise before expiry; otherwise
  they expire worthless.
- **That wrapper positions survive expiry.** They do not. Wrapper `withdraw()` and
  `exercise()` are blocked after expiry, and the underlying series tokens freeze.
- **That the wrapper is collateral or redeemable.** It is not collateral for the trove
  and cannot redeem series collateral or native BTC.
- **That the trove can be closed.** The MUSD/BTC Mezo pool is live, but the available
  BTC and MUSD are insufficient for the close repayment. See §10.
- **That the external Mezo Pools contracts are audited or risk-free.** They are
  third-party contracts.
- **That the web app supports the pool.** The app does not currently surface the
  wrapper or the Mezo Pools pool; this integration is verified via `cast` and the
  explorer.

---

## 9. Limitations and risks

1. **Thin, deployer-seeded pool.** 15 lots and 0.03 MUSD; one 0.00215 MUSD swap moved
   the price by about 15%. A larger trade would move it much more.
2. **No pool-side exercise.** The AMM cannot deliver ERC-20 BTC or call the wrapper.
   Pool LPs are exposed to the option's expiry unless they sell the wrapper.
3. **Post-expiry trap.** The wrapper blocks `withdraw()` and `exercise()` after expiry.
   Wrapper tokens remain transferable but are worthless after the series expires.
4. **Wrapper is not collateral.** It cannot be used to repay the trove, redeem series
   collateral, or convert to native BTC through Roster.
5. **Direct transfers are uncredited.** Sending series position tokens directly to the
   wrapper does not mint wrapper tokens and has no rescue path.
6. **Fractional dust.** Amounts below `1e18` wrapper units cannot be withdrawn or
   exercised. The external buyer retained `0.002735998536819336` wrapper dust.
7. **External protocol risk.** Mezo Pools factory, router, pool implementation, and
   token contracts are outside this repository's audit scope.
8. **No organic liquidity.** The deployer owns essentially all LP supply and can remove
   it. The pool is not a permanent market.
9. **Price is not an oracle.** The pool's marginal price is not used by the series or
   the trove. Exercise still uses the fixed strike.
10. **No audit.** The wrapper and the integration have not been independently reviewed.

---

## 10. MUSD/BTC pool is not a trove-close solution

Mezo testnet has a separate, pre-existing Mezo Pools MUSD/BTC volatile pool at
`0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9`. At the snapshot its reserves were
approximately:

```text
MUSD reserve        = 102,535.526872897298411908
BTC reserve         = 1,303.716239787432999459
implied marginal    = 78,648.65 MUSD/BTC
```

That pool provides an MUSD/BTC swap route. It does **not** solve the trove close:

```text
close repayment required      2,002.057203102504956752 MUSD
vault idle MUSD                 400.000000000000000000 MUSD
owner MUSD                       50.010000000000000000 MUSD
available                       450.010000000000000000 MUSD
shortfall                     1,552.047203102504956752 MUSD

deployer free BTC               0.004697993136676592 BTC
rough MUSD value at spot       ~377.38 MUSD before fees/slippage
available plus free-BTC value  ~827.39 MUSD
remaining gap                  >1,170 MUSD
```

Selling all free BTC would also leave no BTC for gas or settlement, and the trove's
`0.043 BTC` is locked as collateral. The MUSD/BTC pool is therefore evidence that a
swap route exists, not evidence that the trove can be closed. The live trove remains
open and the close is **not demonstrated**.

This distinction matters for the submission: "MUSD/BTC swap availability" is not the
same claim as "Roster position composability", and neither is the same as "the trove
can be closed."

---

## 11. Verification commands

```bash
RPC=https://rpc.test.mezo.org
WRAPPER=0x4726a021ec380a755EBE883BEb800A5d06723E41
POOL=0xED305fEF4c11f95dAe1d144e78B2B62be50965F2
MUSD=0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
FACTORY=0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A

cast call "$WRAPPER" "totalSupply()(uint256)" --rpc-url "$RPC"
cast call "$WRAPPER" "underlyingLots()(uint256)" --rpc-url "$RPC"
cast call "$WRAPPER" "isLive()(bool)" --rpc-url "$RPC"
cast call "$WRAPPER" "balanceOf(address)(uint256)" "$POOL" --rpc-url "$RPC"

cast call "$FACTORY" "getPool(address,address,bool)(address)" \
  "$WRAPPER" "$MUSD" false --rpc-url "$RPC"
cast call "$FACTORY" "isPool(address)(bool)" "$POOL" --rpc-url "$RPC"
cast call "$POOL" "getReserves()(uint256,uint256,uint256)" --rpc-url "$RPC"
cast call "$POOL" "token0()(address)" --rpc-url "$RPC"
cast call "$POOL" "token1()(address)" --rpc-url "$RPC"

cast receipt 0xf9376c6eafd76fbaeb96b1536814fad60c84e9f888b9aecae2af6c5e7fd4bab7 \
  --rpc-url "$RPC"
```

---

## 12. Safe description

> Roster has a live Mezo testnet wrapper/MUSD pool holding actual main-series positions.
> A third-party test account swapped MUSD for wrapper tokens through the Mezo Pools
> router and exercised one lot, delivering ERC-20 BTC and receiving the fixed MUSD
> payout. The pool is small, deployer-seeded, unaudited, and not a market; the wrapper
> is not collateral, cannot redeem series collateral, and cannot settle after expiry.

Anything stronger is not supported by the current evidence.
