# Wave 1 Threat Model and Explicit Assumptions

**Scope:** Roster series, factory, order book, trove vault, position wrapper, Mezo Pools
wrapper/MUSD pool, and read/write web app on Mezo testnet.
**Status:** testnet prototype. No audit. No production funds.
**Last updated:** 2026-10-26.

This model covers the code that exists and the live deployment. It does not claim that
the system is safe. It separates properties enforced by code from properties that
depend on Mezo, on token contracts, on the vault owner, or on market behavior.

---

## 1. Protected assets

| Asset | Where it lives | Why it matters |
| --- | --- | --- |
| Series MUSD collateral | Series contract | Backs active position payouts |
| Series premium | Series contract | Owed to the writer until withdrawn |
| Position-token balances | Series ledger | Represent exercise and expiry rights |
| Native BTC trove collateral | Mezo trove / ActivePool | Backs the vault's MUSD debt |
| ERC-20 BTC exercise proceeds | Vault balance | Belongs to the writer after exercise |
| Escrowed position lots | Order book | Belong to the seller until fill/cancel |
| Wrapper positions | `RosterPositionWrapper` | ERC-20 claims on deposited series lots |
| Pooled wrapper lots | Mezo Pools wrapper/MUSD pool | Deployer-seeded external liquidity |
| MUSD secondary proceeds | Direct buyer-to-seller transfer | Never custodied by Roster |
| Vault owner's MUSD | Owner wallet | Used for trove repayment and close |

The series reserve is **not** the vault owner's free collateral. It is a liability to
position holders and is accounted for separately from the trove. The wrapper is **not**
trove collateral, is **not** redeemable for series collateral or native BTC, and adds no
claim on the trove. A wrapper unit is a claim on deposited series lots only.

---

## 2. Trust boundaries

### 2.1 Trusted or semi-trusted

- **MUSD token** — assumed 18-decimal, exact-transfer, non-rebasing, non-fee-on-transfer.
- **ERC-20 BTC token** — assumed 18-decimal, exact-transfer, truthful `balanceOf`.
- **Mezo BorrowerOperations, TroveManager, PriceFeed, ActivePool, CollSurplusPool** —
  assumed to behave as the deployed protocol.
- **Vault owner** — can open, adjust, borrow, repay, deposit, withdraw, and close the
  trove, subject to code checks. The owner is trusted to manage the trove prudently.
- **Writer** — receives premium and residual collateral; cannot buy or exercise in its
  own address, but can use another address.
- **Demo buyer** — a generated account controlled by the deployer for demonstration.
- **External demo account** — a generated, deployer-funded account used to swap MUSD for
  wrapper and exercise one lot. It is not an independent customer.
- **Mezo Pools Basic PoolFactory, Basic Router, pool implementation, and MUSD/wrapper
  tokens** — third-party contracts treated as deployed. Roster has not audited them.
- **Wrapper** — unowned, immutable adapter trusted only to hold deposited series lots and
  forward exact exercise proceeds. It has no rescue or upgrade path.

### 2.2 Untrusted

- Any address purchasing, transferring, listing, filling, or exercising.
- Any caller of `expire()`.
- Any party reading the app or RPC.
- Any token or contract that is not the configured MUSD/BTC.
- Any Mezo Pools swapper, liquidity provider, or pool participant.
- Any holder or transfer recipient of wrapper units.
- Any front end or wallet extension.

### 2.3 No privileged protocol owner

- Factory: no owner, no pause, no allowlist.
- Series: immutable terms; no owner, pause, upgrade, rescue, or fee recipient.
- Order book: no owner, no pause, no fee, no upgrade.
- Vault: owner can manage the trove and owner-controlled withdrawals, but cannot mint
  positions, alter series terms, or take series collateral outside `finalize()`/expiry.
- Wrapper: no owner, pause, upgrade, fee, or rescue. Its only privileged actions are the
  user-called `deposit`, `withdraw`, and `exercise`.
- Mezo Pools pool: controlled by third-party factory/router code and by its LPs. It is not
  a Roster contract.

---

## 3. Core invariants

At successful top-level transaction boundaries:

1. `collateral_balance_raw == reserved_raw + excess_raw`.
2. `reserved_raw == active_lots * strike_per_lot_raw`.
3. Before expiry release, `totalSupply() == active_lots`.
4. After `expire()`, collateral, reserve, excess, and active lots are zero; token supply
   and balances remain frozen.
5. `total_deposited_raw - total_payouts_raw - expiry_release_raw ==
   collateral_balance_raw`.
6. `musd.balanceOf(series) >= collateral_balance_raw + premium_balance_raw` after
   completed operations.
7. Vault `idleMUSD() == MUSD balance - reservedMUSD()`.
8. Vault `reservedMUSD() == series.expiry_release_raw - expiryForwarded`.
9. `finalize()` forwards an expiry release at most once.
10. `closeTrove()` preserves MUSD reserved for an already-released series expiry.
11. `wrapper.totalSupply() == wrapper.underlyingLots() * wrapper.UNIT()`.
12. A wrapper `exercise()` burns whole lots, delivers exactly `lots * 1e12` ERC-20 BTC to
    the series, and forwards exactly the MUSD received.

These are transaction-boundary properties. During an external token callback, effects-
first bookkeeping can temporarily lead the incoming asset balance; the reentrancy guard
prevents nested lifecycle operations. Invariant 11 can be broken only by sending series
tokens directly to the wrapper, which are uncredited and unrecoverable; the wrapper's own
`deposit`/`withdraw`/`exercise` paths preserve it.

---

## 4. Adversary capabilities considered

- Non-writer users can purchase, transfer, approve, list, fill, cancel, and exercise.
- Users can submit zero, excessive, post-maturity, or unauthorized operations.
- A configured ERC-20 can call back into the series during `transferFrom`.
- A token transfer can revert; effects before the transfer must roll back atomically.
- Users can send MUSD/BTC directly to the series without using lifecycle functions.
- Calls can arrive during maturity/limbo and after finalization.
- A writer can use a second address to buy or exercise.
- A seller can forget to cancel a listing before maturity.
- A holder can forget to exercise before maturity.
- A vault owner can make poor trove decisions, including unsafe borrowing.
- A third party can call `expire()` and send the release to the vault.
- A third party can fill or not fill an ask; liquidity is not guaranteed.
- A wrapper holder can transfer, approve, or fail to settle before expiry.
- A Mezo Pools swapper can move the pool price or drain thin liquidity.
- An AMM or other contract can hold wrapper units but cannot call `exercise()` on them.
- A malicious front end can display false data; users must verify on-chain.

---

## 5. Threat table

### 5.1 Series contract

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Reentrancy during token transfer | `nonReentrant` on lifecycle and position-moving functions; effects-first bookkeeping | A callback can still observe transient state; no nested lifecycle call succeeds |
| Fee-on-transfer or rebasing MUSD/BTC | Exact before/after balance checks; atomic rollback | A malicious token that lies about balances is out of scope |
| Writer buys its own series | Explicit writer rejection in `purchase` | Writer can use another address |
| Writer exercises | Explicit writer rejection in `exercise` | Writer can use another address |
| Transfer to writer/series/zero | `_checkTransferAllowed` rejects | A writer-controlled alternate address is allowed |
| Purchase beyond capacity | `excess_raw` check | Capacity is small; no deep liquidity |
| Rounding exploit | Strike must be divisible by 1e6; per-lot payout is exact | None identified in the tested domain |
| Zero-value operations | Explicit zero checks | None identified |
| Double expiry release | `expired` flag and idempotent `expire()` | None identified |
| Exercise after expiry | `_requireLive` check | None identified |
| Transfer after expiry | Maturity check | None identified |
| Direct token transfers stranded | Documented; no rescue | Permanent loss for the sender |
| Premium withdrawn from reserve | Premium tracked separately | None identified |
| Unsolicited tokens | Not credited; no rescue | Permanent loss |

### 5.2 Order book

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Unregistered series listed | Factory `isSeries` check | A registered but low-quality series can still be listed |
| Mismatched MUSD series | Constructor and listing checks | None identified |
| Seller loses escrow at expiry | Documented; listings freeze at maturity | Seller must cancel before expiry |
| Fill after expiry | Maturity check | None identified |
| Cancel by non-seller | Seller check | None identified |
| Overfill | Remaining-lots check | None identified |
| Reentrancy on MUSD/position transfer | `nonReentrant` | Trusted token assumption |
| No buyer | Ask-only book | Liquidity is not guaranteed |
| Price mistake | Seller chooses price | No oracle or price protection |

### 5.3 Trove vault

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Unauthorized owner actions | `onlyOwner` | Owner key compromise is catastrophic |
| Trove below application ICR | `minICR` check after open/borrow/collateral changes | Price can move after the check; Mezo MCR is 110% |
| Liquidation | No liquidation protection; ICR buffer only | BTC price fall or debt rise can liquidate |
| Interest accrual | Debt read from TroveManager; close updates interest | Interest continues between reads |
| Close shortfall | `closeTrove()` requires enough MUSD; reserved proceeds preserved | Live account cannot currently fund the shortfall |
| Native BTC sent by wrong address | `receive()` accepts only ActivePool/CollSurplusPool | A protocol upgrade changing senders would break receipt |
| ERC-20 BTC confused with native BTC | Separate functions and accounting | User error remains possible |
| Series reserve used to repay trove | Not automatic; reserve stays in series | Owner may misunderstand the separation |
| Third-party `expire()` | `finalize()` handles release idempotently | Owner must still call `finalize()` to forward |
| Double forwarding | `expiryForwarded` accounting | None identified |
| Premium double withdrawal | Series premium balance and vault forwarding | None identified |
| Borrowing fee underfunding | Tests model fee; live check needed | Fee is governance-configurable |
| Gas compensation confusion | Close repayment excludes 200 MUSD gas compensation | Users may misread debt |
| Owner abandons trove | No keeper or automation | Debt and liquidation risk persist |

### 5.4 Position wrapper

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Reentrancy through series or BTC token | `nonReentrant` on `deposit`, `withdraw`, `exercise`; effects-first bookkeeping | Trusted token assumption |
| Wrapper mints unbacked units | `deposit` pulls exact lots and mints `lots * 1e18`; `underlyingLots` tracks deposits | Direct series-token transfers are uncredited but do not mint wrapper units |
| Fractional withdrawal/exercise | Whole-lot modulo check | Fractional units can be transferred but not redeemed |
| Settlement after expiry | `isLive` check blocks `deposit`, `withdraw`, and `exercise` | Wrapper tokens remain transferable but worthless after expiry |
| Exercise payout diverted | MUSD is forwarded directly to the caller; no owner or fee | A malicious BTC token callback is out of scope |
| Series transfer restriction bypass | Wrapper calls series `exercise`/`transfer`; `withdraw` to the writer reverts | Writer can still use another address, as with direct series tokens |
| Direct series tokens stranded | Documented; no rescue | Permanent loss for the sender |
| Wrapper used as collateral | Not accepted by the trove or series | External protocols may mistakenly value it; not Roster's claim |
| Wrapper upgrade/admin abuse | No owner, proxy, pause, or rescue | Immutable bugs cannot be fixed |

### 5.5 Mezo Pools wrapper/MUSD pool

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Thin liquidity / price manipulation | None in Roster; pool is third-party | Deployer seeded 15 lots and 0.03 MUSD; deployer holds essentially all LP supply and can remove it |
| Pool cannot exercise | Documented; pool-held lots must be sold before expiry | Pool-held lots may expire worthless |
| Impermanent loss / adverse selection | Standard AMM risk; no Roster protection | LPs can lose value |
| Router or factory vulnerability | Third-party code; not audited here | A bug could drain pooled assets |
| Fake pool or token | Verify factory `getPool`/`isPool` and token addresses | Users can be phished by lookalike contracts |
| Wrapper price treated as series value | No oracle integration; marginal price is pool-only | Observers may over-interpret a thin quote |
| Liquidity removed before expiry | No lock or incentive | Deployer/LP can withdraw at any time |

### 5.6 Factory

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Malicious series registration | Factory deploys the series itself; no arbitrary address registration | A bad series can still be created with bad terms |
| Duplicate series | Permissionless; duplicates allowed | No uniqueness guarantee |
| Factory owner abuse | No owner or admin | None in code |
| Asset mismatch | Series constructor validates assets | Trusted token assumption |

### 5.7 Web app

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Phishing/false front end | Static code; users can inspect and self-host | A compromised host could lie |
| Malicious RPC | Public RPC is trusted for reads | A malicious RPC can return false data |
| Wallet drain | App only requests approvals and calls documented functions | Users must inspect wallet prompts |
| Approval overreach | App approves exact amounts, not unlimited | A compromised token contract remains a risk |
| Chain confusion | App checks chain 31611 and offers switch/add | User can still sign on the wrong chain elsewhere |
| Key exposure | App never asks for a private key | Wallet extension compromise is out of scope |
| Stale data | Periodic refresh and manual refresh | No backend indexer; reads can lag |
| No wallet E2E | Read-only five-page browser pass; exact approvals | Wallet interaction and transaction UI bugs may remain |

---

## 6. Economic and market risks

- **No organic demand.** The buyer and external account are generated. A fill or swap
  does not prove a market.
- **No premium discovery.** The writer sets a fixed premium. It may be mispriced.
- **Small capacity.** 18,750 lots maximum at the initial deposit; 74 active.
- **No market maker or keeper.** Expiry is lazy; holders must act.
- **No liquidity guarantee.** The order book may have no buyer.
- **Trove liquidation.** 0.043 native BTC backs ~2,202 MUSD at ~156.9% ICR. A price fall
  toward 110% MCR is a real risk.
- **Interest accrual.** Debt grows; the close shortfall grows.
- **Thin wrapper pool.** The Mezo Pools wrapper/MUSD pool is deployer-seeded with 15 lots
  and 0.03 MUSD. The deployer holds essentially all LP supply and can remove it. The
  marginal price moved ~15% on a 0.00215 MUSD swap.
- **MUSD/BTC swap does not close the trove.** A Mezo Pools MUSD/BTC pool exists, but the
  deployer's free BTC and available MUSD leave a gap above 1,170 MUSD, before fees and
  gas. It is not a close solution.
- **Post-expiry wrapper dead end.** The wrapper blocks settlement after expiry; wrapper
  tokens are transferable but worthless, and pooled lots cannot be exercised by the AMM.
- **MUSD depeg/issuer risk.** Not modeled by the contracts.
- **BTC price volatility.** The put's economics and the trove's health both depend on it.
- **No MEZO-token incentive.** There is no governance-token subsidy or yield.

---

## 7. Deliberate policy restrictions

- The designated writer cannot purchase, receive position tokens, or exercise. This is
  demo hygiene, not Sybil resistance.
- Positions cannot be transferred to the writer, the series contract, or the zero
  address.
- Position transfers freeze at/after maturity.
- `approve()` is unguarded because it changes allowance only; moving and lifecycle
  functions are guarded.
- `expire()` is permissionless and idempotent after maturity.
- There is no pre-expiry excess withdrawal, emergency rescue, upgrade, pause, fee
  recipient, or privileged post-deployment setter.
- The order book is ask-only. There are no bids, matching, fees, or keeper rewards.
- The vault owner cannot take series collateral except through expiry release and
  `finalize()`.
- The wrapper is unowned and cannot mint series positions, change terms, pause transfers,
  or upgrade. It blocks `deposit`, `withdraw`, and `exercise` after expiry.
- The wrapper/MUSD pool is an external Mezo Pools market, not a Roster-controlled venue.
  Roster does not seed it with protocol funds, incentivize it, or guarantee its liquidity.

---

## 8. Assumptions and out-of-scope risks

- MUSD and ERC-20 BTC are verified, 18-decimal, exact-transfer tokens with truthful
  `balanceOf`.
- Mezo protocol contracts behave as deployed and documented.
- The price feed is honest and available.
- The vault owner manages the trove responsibly and keeps the owner key safe.
- The demo buyer and external account are not independent customers.
- The Mezo Pools factory, router, pool implementation, and tokens are assumed to behave as
  deployed and are not audited by this project.
- The wrapper is assumed to hold exactly the series lots recorded in `underlyingLots`;
  direct unsolicited series-token transfers are out of scope.
- The testnet environment is not economically adversarial.
- No audit has been performed.
- No formal verification has been performed.
- No liquidation, redemption, or MEV simulation has been performed.
- No production incident response, monitoring, or alerting exists.
- No mainnet deployment exists.
- No legal, regulatory, or securities analysis is provided.
- No guarantee that native BTC and ERC-20 BTC are convertible.

---

## 9. Security conclusions

The code has meaningful local protections: reentrancy guards, exact-transfer checks,
reserve accounting, expiry idempotency, writer restrictions, ICR checks, a protected
close path, and a whole-lot wrapper with 1:1 backing. The test suite covers those
properties and the live deployment demonstrates the main flows, including an external
swap and exercise.

The code does **not** have:

- an audit, including of the wrapper or Mezo Pools integration;
- formal verification;
- a liquidation keeper;
- a deep or organic market;
- a way to close the live trove with current balances;
- a main-series expiry demonstration;
- pool-side exercise or a post-expiry wrapper unwind;
- a wallet transaction walkthrough in the app;
- wrapper or pool support in the app;
- a production-ready front end.

The correct conclusion is:

> Roster is a working testnet mechanism with real Mezo integration, verified lifecycle
> transactions, and a demonstrated external wrapper/MUSD market over actual positions,
> but it is not audited, not production-ready, and not a demonstration of organic demand,
> organic liquidity, or trove profitability.
