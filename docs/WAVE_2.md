# Wave 2 Resubmission — Roster

**Project:** Roster Finance  
**Track:** Track 1 — DeFi only  
**Category:** Bitcoin options and credit  
**Network:** Mezo testnet, chain ID `31611`  
**Wave 1 baseline:** commit `0ff72da` (core stack and five-page app; 82/82 tests; no
external composability path)  
**Current evidence:** commit `b6ecf8d`, recorded by `bfb52c0` (wrapper, Mezo Pools
integration, 91/91 tests)  
**Status:** **Wave 2 proposal.** The work described under “What Wave 2 will deliver” is
not built yet. The live evidence below is Wave 1 plus the post-Wave-1 composability work.

> This document answers the two questions a Wave 2 resubmission must answer without
> ambiguity:
>
> 1. **What changed since Wave 1?**
> 2. **What exactly will be delivered in Wave 2?**
>
> It also records what did **not** change and what must not be claimed. The canonical
> project record remains [`../README.md`](../README.md). Where this document and the chain
> disagree, the chain and the README win.

---

## Contents

1. [Resubmission at a glance](#1-resubmission-at-a-glance)
2. [Wave 1 baseline](#2-wave-1-baseline)
3. [What changed since Wave 1](#3-what-changed-since-wave-1)
4. [Current verified state](#4-current-verified-state)
5. [What Wave 2 will deliver](#5-what-wave-2-will-deliver)
6. [Timeline and milestones](#6-timeline-and-milestones)
7. [Wave 2 definition of done](#7-wave-2-definition-of-done)
8. [What Wave 2 will not claim](#8-what-wave-2-will-not-claim)
9. [Risks, dependencies, and mitigations](#9-risks-dependencies-and-mitigations)
10. [How to verify the current submission](#10-how-to-verify-the-current-submission)
11. [Copy-ready resubmission answers](#11-copy-ready-resubmission-answers)
12. [Related documents](#12-related-documents)

---

## 1. Resubmission at a glance

| Question | Answer |
| --- | --- |
| What is Roster? | A fixed-strike, fixed-expiry, physically settled BTC put mechanism on Mezo. A trove-backed writer borrows MUSD against native BTC and funds a series. Buyers pay a fixed MUSD premium; holders can exercise by delivering ERC-20 BTC for an exact MUSD payout, or sell lots through an ask book. |
| What was delivered in Wave 1? | Factory, series, ask book, per-series trove vault, five-page Vite app, a live main series, a live expiry demo, primary purchase, secondary fill, physical exercise, premium withdrawal, and 82 passing tests. |
| What changed since Wave 1? | A standard `RosterPositionWrapper` over **actual** series lots, a live Mezo Pools wrapper/MUSD pool, a third-party account that acquired wrapper exposure through the router and exercised one lot, 9 wrapper tests (91 total), expanded evidence docs, and corrected native-BTC/ERC-20-BTC disclosures. No core series terms changed. |
| What will Wave 2 add? | A hosted, wallet-tested app with wrapper/pool support and automated E2E coverage; a complete vault-backed lifecycle on a new right-sized series, including `finalize()` and `closeTrove()`; at least three independent testnet users; a scoped independent security review with remediation; and monitoring/runbooks. |
| Is Wave 2 a mainnet launch? | **No.** Wave 2 is testnet-only. Mainnet remains a later gate after audit and operational readiness. |
| Is the existing main trove closable? | **No, not with current balances.** The shortfall is about `1,552.05 MUSD`. Wave 2 will prove the close path on a new, deliberately small, fundable series rather than misrepresent the main trove. |
| Is there organic demand? | **No.** The buyer and external account are generated demo accounts, and the pool is deployer-seeded. Wave 2 will test with independent users but will not call testnet participation “demand.” |
| Does this use MEZO? | **No.** The integration is MUSD, a Mezo trove, Mezo’s ERC-20 BTC interface, Mezo’s price feed, and a Mezo Pools pool. No MEZO governance-token usage is claimed. |

The short version:

> Wave 1 proved the mechanism. The post-Wave-1 work proved that actual Roster positions can
> leave Roster through an external Mezo Pools venue. Wave 2 is about closing the remaining
> validation gaps: wallet-complete UX, a full vault lifecycle including close, independent
> testnet users, and a reviewed, observable deployment.

---

## 2. Wave 1 baseline

Wave 1 is the submission state at commit `0ff72da` (with the CI formatting fix in
`50ce21a`). It was a real testnet stack, not a mockup.

### 2.1 What Wave 1 delivered

| Deliverable | Wave 1 state | Evidence |
| --- | --- | --- |
| `RosterSeriesFactory` | Live | Factory `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F`; 4 tests |
| `RosterBtcPutSeries` | Live main and demo | Main `0xC231…5b92`; demo `0xCC6b…FA43`; 36 tests |
| `RosterOrderBook` | Live | `0xc97B…cd25`; 13 tests |
| `RosterTroveWriter` | Live | `0x214e…A331`; 23 tests |
| Mezo trove | Open | `0.043` native BTC; `2,202.001777260997830208` MUSD debt at the Wave 1 snapshot |
| Main-series lifecycle | Live | 100 lots purchased, 50 listed, 25 filled, 25 exercised for `2 MUSD`, `0.1 MUSD` premium withdrawn |
| Demo expiry | Live | Expired `2026-10-25`; `20 MUSD` released; 10 tokens frozen |
| Web app | Implemented and building | Five pages; read-only desktop/mobile browser pass; no wallet transaction |
| Tests | **82/82** default and CI | 36 series + 23 vault + 13 book + 4 factory + 6 invariants |
| Audit | **None** | Do not claim otherwise |
| Organic demand | **None observed** | Buyer was a generated demo account |
| Trove close | **Not demonstrated** | MUSD shortfall |
| Main-series expiry/finalize | **Not reached** | Expiry `2026-11-24 11:17:06 UTC` |

Wave 1 snapshot values:

```text
main-series active lots          75
main-series collateral           1,498.00 MUSD
main-series cumulative payouts   2.00 MUSD
main-series premium balance      0 MUSD
trove native collateral          0.043 BTC
trove debt                       2,202.001777260997830208 MUSD
trove ICR                        156.99%
tests                            82/82
external composability           none
position wrapper                 not deployed
Mezo Pools wrapper/MUSD pool     not deployed
```

### 2.2 The honest Wave 1 gap

Wave 1 had a working core mechanism, but two credibility gaps remained:

1. **No external composability over actual Roster positions.** A series token is
   zero-decimal and protocol-restricted. Without an adapter and an external venue, the
   claim that Roster positions were composable was weak.
2. **No wallet transaction through the app.** The app built and loaded live data, but no
   wallet signature, confirmation, or transaction had been exercised through the UI.

Wave 1 also could not show a vault-bound `finalize()` or `closeTrove()`, because the main
series had not matured and the main trove was underfunded for repayment.

---

## 3. What changed since Wave 1

The changes are deliberate and narrow. They address the composability gap; they do not
rewrite the core mechanism or add unrelated features.

### 3.1 Change summary

| Change | Type | Evidence | Why it matters |
| --- | --- | --- | --- |
| Added `RosterPositionWrapper` | Contract | [`src/RosterPositionWrapper.sol`](../src/RosterPositionWrapper.sol); deployed at `0x4726…3E41`; 9 tests | Converts actual zero-decimal series lots into a standard 18-decimal ERC-20 (`1e18 = 1 lot`) that external venues can hold and transfer. |
| Added a live Mezo Pools pool | External integration | Pool `0xED305…65F2`; factory `isPool == true`; 15 actual lots and `0.03 MUSD` seeded | Proves a third-party AMM can hold wrapper tokens backed by actual Roster positions. |
| Added an external settlement demonstration | Live evidence | External account `0x1Ed2…5Ee3C` swapped `0.00215 MUSD` for wrapper through the Mezo router, then exercised 1 lot for `0.08 MUSD` | Proves an address with no direct series position can acquire wrapper exposure and settle through the series. |
| Expanded tests from 82 to 91 | Test coverage | 9 wrapper tests; default and CI profiles both **91/91** | Covers wrapper backing, whole-lot rules, expiry blocking, direct-transfer handling, and exact forwarding. |
| Expanded evidence and disclosures | Documentation | [`COMPOSABILITY.md`](COMPOSABILITY.md), updated deployment record, validation status, threat model, test output, app docs, deployment JSON | Makes the external path and its limitations independently checkable. |
| Corrected native-BTC vs ERC-20-BTC language | App and docs | “Two BTC accounting paths,” not two freely interchangeable assets | Avoids implying that locked trove collateral can be spent or converted through Roster. |
| Tightened submission positioning | Positioning | Track 1 only; MUSD only; no MEZO governance usage | Keeps the resubmission honest rather than adding a token integration to tick a box. |

### 3.2 The composability change in one paragraph

The wrapper holds **actual main-series lots**, not a synthetic token. The deployer
deposited 20 lots into the wrapper and seeded a Mezo Pools volatile pool with 15 wrapper
lots and `0.03 MUSD`. A separate generated account, with no direct series position,
approved `0.00215 MUSD` to the Mezo Pools Basic Router, swapped into
`1.002735998536819336` wrapper units, and called `wrapper.exercise(1e18)`. It delivered
`0.000001` ERC-20 BTC and received `0.08 MUSD` from the series. The wrapper stayed 1:1
backed: after the exercise, wrapper supply was `19e18` and `underlyingLots()` was `19`.

That path is more than a wrapper and more than an MUSD/BTC swap: the external account
settled a claim backed by actual Roster series positions.

### 3.3 What changed in live state

| Field | Wave 1 snapshot | Current snapshot | Cause |
| --- | --- | --- | --- |
| Main-series active lots | `75` | `74` | One lot exercised through the wrapper |
| Main-series collateral | `1,498.00 MUSD` | `1,497.92 MUSD` | One `0.08 MUSD` strike paid |
| Main-series total payouts | `2.00 MUSD` | `2.08 MUSD` | Wrapper exercise |
| Main-series premium | `0 MUSD` | `0 MUSD` | Already withdrawn in Wave 1 |
| Position wrapper | Not deployed | `19e18` supply / 19 lots | Added after Wave 1 |
| Wrapper/MUSD pool | Not deployed | `13.997264001463180664` wrapper / `0.03214914` MUSD | Deployer seed plus external swap |
| Trove debt | `2,202.001777260997830208 MUSD` | `2,202.057203102504956752 MUSD` | Interest accrual |
| Trove ICR | `156.99%` | `156.856%` | Interest and BTC price |
| Tests | `82/82` | `91/91` | 9 wrapper tests |

The current snapshot was taken at block `16,379,045`, **2026-10-26 10:15:56 UTC**. Debt,
interest, ICR, pool reserves, and balances move.

### 3.4 What this proves — and what it does not

What the new work proves:

- A Mezo Pools volatile pool recognizes and holds a wrapper backed 1:1 by actual Roster
  series lots.
- A third-party address can acquire wrapper exposure through the Mezo router and settle one
  lot through the wrapper, delivering ERC-20 BTC and receiving the fixed MUSD payout.
- The wrapper’s approval, `transferFrom`, `exercise`, and exact MUSD forwarding paths work
  against live Mezo assets.
- The series accounting remained consistent: one lot burned, `1e-6` BTC delivered,
  `0.08 MUSD` paid, active lots and reserve reduced by one lot.

What it does **not** prove:

- Organic demand or fair pricing. The external account was generated and funded by the
  deployer.
- Deep liquidity. The pool is deployer-seeded, thin, and has essentially all LP supply held
  by the deployer.
- That the pool can exercise its own positions. The AMM cannot call `wrapper.exercise()`;
  pooled lots must be sold to an exercising address before expiry.
- That wrapper positions survive expiry. Wrapper `deposit`, `withdraw`, and `exercise` are
  blocked after expiry; the tokens are worthless after the series expires.
- That the wrapper is collateral, is redeemable for series collateral/native BTC, or can
  convert native BTC into ERC-20 BTC.
- That the trove can be closed, the main series has matured, or the app is wallet-tested.

### 3.5 What did not change

These are unchanged from Wave 1 and remain open:

- Core series, factory, order book, and vault terms and contracts.
- Main-series strike, premium, lot size, expiry, and writer.
- The five-page app structure; the wrapper and pool are **not** in the app.
- The app’s only browser evidence is a read-only pass at desktop and mobile widths. It
  predates the wrapper/pool, observed `75` active lots and `1,498 MUSD` collateral, and did
  not connect a wallet.
- No wallet transaction through the UI, no automated browser E2E suite, no hosted demo.
- No audit or independent security review.
- No organic demand, market-based premium discovery, or independent liquidity.
- Main-series expiry/finalization has not occurred.
- The main trove remains open and underfunded for close.
- Native BTC trove collateral and ERC-20 BTC remain separate accounting paths.
- No MEZO governance-token integration.

---

## 4. Current verified state

### 4.1 Addresses

All addresses are on **Mezo testnet, chain ID `31611`**.

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
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` |

Explorer base: `https://explorer.test.mezo.org`.

### 4.2 Test and build evidence

```text
forge fmt --check                 exit 0
forge build                       succeeds; lint warnings only
forge test -vvv                   91 passed, 0 failed
FOUNDRY_PROFILE=ci forge test     91 passed, 0 failed
python3 scripts/static_validate.py  PASS
cd app && npm run build           PASS
```

| Suite | Tests |
| --- | ---: |
| `RosterBtcPutSeriesTest` | 36 |
| `RosterTroveWriterTest` | 23 |
| `RosterOrderBookTest` | 13 |
| `RosterSeriesFactoryTest` | 4 |
| `RosterPositionWrapperTest` | 9 |
| `SeriesInvariantTest` | 6 invariants |
| **Total** | **91** |

CI for the composability commit: run
[`40314178418`](https://github.com/Chidubemkingsley/Roster-mezo/actions/runs/40314178418).
The docs-only CI record commit is run
[`40314681555`](https://github.com/Chidubemkingsley/Roster-mezo/actions/runs/40314681555).

### 4.3 Current snapshot

```text
main series active lots          74
main series collateral           1,497.92 MUSD
main series reserved             5.92 MUSD
main series excess               1,492.00 MUSD
main series cumulative payouts   2.08 MUSD
wrapper total supply             19e18
wrapper underlying lots          19
pool MUSD reserve                0.03214914 MUSD
pool wrapper reserve             13.997264001463180664
trove native collateral          0.043 BTC
trove debt                       2,202.057203102504956752 MUSD
trove ICR                        156.856%
```

### 4.4 Still-open gaps carried into Wave 2

| Gap | Current state | Wave 2 response |
| --- | --- | --- |
| Wallet transaction through the app | Never performed | Wallet-tested hosted app and recorded live flows |
| Wrapper/pool in the app | Not surfaced | Read views plus wrapper deposit/withdraw/exercise and pool metrics |
| Automated browser E2E | None | Playwright flows in CI plus a separate live-wallet run |
| Full vault lifecycle | `finalize()`/`closeTrove()` not demonstrated live | New right-sized vault-backed series taken through expiry, finalize, and close |
| Main-series expiry | `2026-11-24`, not reached | Capture if it falls inside Wave 2; otherwise use the new cohort |
| Trove close on the main vault | Blocked by ~`1,552.05 MUSD` shortfall | Do not pretend; prove close on a fundable cohort and publish the main-vault math |
| Independent users | None; accounts are generated | At least 3 non-deployer testnet users, with honest reporting |
| Audit | None | Scoped independent review, remediation, and monitoring — not an audit claim unless completed |
| Organic liquidity | None; deployer-seeded pool | Treat as a test venue; no manufactured “liquidity” claim |

---

## 5. What Wave 2 will deliver

Wave 2 is the bridge from a working testnet mechanism to a **fully demonstrated,
externally validated testnet product**. It is not a mainnet launch, and it does not add
unrelated features to tick boxes.

The scope has four workstreams. Workstreams 1, 2, and 4 are delivery gates. Workstream 3 is
an external-validation target; if independent users do not materialize, Wave 2 reports the
shortfall instead of substituting generated accounts. No workstream is silently dropped.

### 5.1 Workstream 1 — Wallet-complete, hosted app

**Goal:** make the existing five-page app a complete testnet client, including the external
composability path, with real wallet evidence.

Deliverables:

- Host the production build on a public static URL.
- Connect an injected wallet on Mezo testnet and exercise the primary flows live:
  purchase, list, fill-all, cancel, exercise, and owner premium withdrawal.
- Add a wrapper/pool view that shows:
  - wrapper address, backing (`totalSupply()` vs `underlyingLots()`), and `isLive()`;
  - pool reserves, implied marginal price, and a direct Mezo Pools/explorer link;
  - explicit warnings that the pool is thin, deployer-seeded, cannot exercise, and that
    wrapper positions cannot be settled after expiry.
- Add wrapper actions: `deposit(lots)`, `withdraw(whole lots)`, and `exercise(whole lots)`,
  with exact approvals, whole-lot validation, and post-expiry blocking.
- Add clear transaction lifecycle states: pending, confirmed, rejected, wrong chain, and
  reverted.
- Add automated browser tests for the main UI flows using a deterministic local fixture
  and mock wallet. Run them in CI.
- Perform and record one manual live-wallet pass on Mezo testnet, separate from the
  automated suite.

Acceptance criteria:

- The app is reachable at a stable public URL.
- All five pages load with no uncaught exceptions or horizontal overflow at desktop and
  mobile widths.
- A non-deployer wallet completes at least one live purchase and one live exercise
  through the UI; the transaction hashes and confirmation screenshots are recorded.
- A live wrapper deposit and a live wrapper exercise are completed through the UI.
- The automated browser suite covers the same flows against the local fixture and passes
  in CI.
- The app displays the wrapper/pool limitations without implying organic liquidity or
  post-expiry settlement.

Evidence to publish: hosted URL, transaction hashes, screenshots, a short walkthrough
video, Playwright output, and CI run link.

### 5.2 Workstream 2 — Complete vault lifecycle, including close

**Goal:** prove the path that the live main deployment cannot yet show: a vault-bound series
that matures, releases collateral, forwards it through `finalize()`, and lets the owner
close the trove.

Deliverables:

- Deploy a new, deliberately small vault-backed series with a short expiry (target:
  14 days).
- Size the trove and series deposit so the close repayment is fundable from existing
  testnet balances; do not assume new external capital.
- Exercise the full lifecycle on testnet:
  1. create series and bind a new vault;
  2. open the trove with native BTC and borrow MUSD;
  3. fund the series;
  4. purchase lots from a separate account;
  5. optionally fill a secondary ask or exercise a lot before expiry;
  6. let the series mature and call `expire()`;
  7. call vault `finalize()` and verify the expiry release is forwarded exactly once;
  8. call `closeTrove()` and verify debt repayment, native collateral return, and final
     balances.
- Record the close arithmetic before and after: debt, gas compensation, repayment,
  collateral returned, and any owner-funded shortfall.
- For the existing main series: if its `2026-11-24` expiry falls inside the Wave 2 window,
  record its `expire()` and `finalize()`; if not, state that it remains pending and rely on
  the new cohort for the lifecycle proof.
- Do not claim the existing main trove was closed unless it actually is.

Acceptance criteria:

- A new vault-backed series completes every step above with receipt status `1`.
- `finalize()` forwards the series release exactly once.
- `closeTrove()` succeeds, the trove debt is repaid, and native BTC collateral is returned.
- The close math is documented and reconciles with on-chain balances.
- The main-series status is reported separately and accurately.
- The app’s vault page reflects the new lifecycle state where applicable.

Evidence to publish: addresses, deployment and lifecycle transaction hashes, block
numbers, before/after balance tables, and a short runbook.

### 5.3 Workstream 3 — Independent testnet validation

**Goal:** replace the generated-account demonstration with evidence from users the
deployer does not control, without misrepresenting testnet participation as demand.

Deliverables:

- Recruit at least three independent testnet wallets.
- Each participant completes:
  - one primary purchase; and
  - one secondary fill or one wrapper action (deposit, withdraw, or exercise).
- Provide testnet gas/settlement assets only as needed, and disclose every transfer from
  the deployer.
- Collect short written feedback on usability, comprehension of expiry risk, and the
  wrapper/pool warnings.
- Publish the wallet addresses, transaction hashes, and a summary of what each participant
  did.

Acceptance criteria:

- At least three distinct non-deployer wallets complete the required actions.
- No participant is described as a customer, an investor, or organic demand.
- If fewer than three participants complete the flow, report the actual number, mark the
  workstream partial, and state the reason; do not substitute generated accounts.
- The feedback is summarized with both positive and negative findings.

This workstream validates usability and external participation. It does **not** claim
product-market fit, premium discovery, or liquidity demand.

### 5.4 Workstream 4 — Security review, hardening, and operations

**Goal:** reduce the gap between “testnet demo” and “reviewable prototype,” without
pretending a review is an audit.

Deliverables:

- Add wrapper invariant/fuzz coverage for:
  - `totalSupply == underlyingLots * UNIT` through deposit/withdraw/exercise;
  - whole-lot enforcement and fractional-balance behavior;
  - post-expiry blocking;
  - direct series-token transfers and uncredited balances;
  - exact MUSD forwarding.
- Add adversarial tests for the order book’s maturity behavior and the vault’s
  expiry-release preservation.
- Commission a scoped independent review of the series, vault, order book, wrapper, and
  Mezo Pools integration. Publish the report and a remediation log.
- Add a read-only monitoring script or dashboard for:
  - trove debt, collateral, and ICR;
  - main-series expiry and finalization status;
  - wrapper backing and pool reserves;
  - order-book expiry exposure.
- Write an incident/close runbook: what to do if ICR approaches the liquidation threshold,
  a series matures, or the wrapper/pool needs to be unwound.
- Remediate high- and medium-severity findings before calling Wave 2 complete.

Acceptance criteria:

- New wrapper invariant/fuzz tests pass in default and CI profiles.
- The review report is public, with findings and fixes linked to commits.
- Monitoring produces an observable alert/readout for the defined thresholds.
- The runbook is checked against the live deployment.
- No “audited” or “production-ready” claim is made unless an audit is actually completed.

---

## 6. Timeline and milestones

Timelines are measured from Wave 2 acceptance, not from the date of this document.

| Window | Milestone | Evidence gate |
| --- | --- | --- |
| Days 1–10 | Hosted build; hosted URL and deployment notes | Public URL; five pages load |
| Days 1–20 | Live wallet pass for purchase, list, fill, cancel, exercise, premium | Transaction hashes, screenshots, video |
| Days 10–30 | Wrapper/pool UI and wrapper actions; automated Playwright suite | UI demo; CI E2E run; live wrapper tx |
| Days 20–40 | New right-sized vault-backed series created and funded | Addresses; deployment and funding receipts |
| Days 30–55 | New series matures; `expire()`, `finalize()`, and `closeTrove()` demonstrated | Full lifecycle transaction ledger; close arithmetic |
| Days 35–65 | Independent users complete purchase plus secondary/wrapper actions | Wallet addresses; receipts; feedback summary |
| Days 40–75 | Scoped independent review; high/medium fixes; monitoring and runbook | Public report; remediation commits; monitor output |
| Days 70–90 | Final documentation, demo video, and submission evidence refresh | Docs match chain; no stale claims; CI green |

### 6.1 Milestone logic

- **The app is the first gate.** Without a hosted, wallet-tested app, the submission still
  looks like a contract demo with a static front end.
- **The new cohort is the lifecycle gate.** The main series expires on `2026-11-24`, which
  may fall outside the Wave 2 window. A new short-dated series is the controllable proof.
- **The independent users are the external-validation gate.** Three wallets do not prove
  demand, but they do prove that the flow is usable by someone other than the deployer.
- **The review is the trust gate.** It is a scoped review, not a substitute for a full
  audit, and it must be described precisely.

### 6.2 Dependencies

- Mezo testnet remains available, and MUSD/BTC test assets can be sourced.
- The new trove can be sized so its close is fundable from existing testnet balances.
- Independent testers are available and willing to use a testnet product.
- The security review can be completed within the Wave 2 window.

If a dependency fails, Wave 2 reports the failure and does not substitute a generated
account, an imaginary close, or an “audit” label.

---

## 7. Wave 2 definition of done

Wave 2 is complete only when all of the following are true:

- [ ] Hosted app is live and publicly reachable.
- [ ] A non-deployer wallet completes a live purchase and exercise through the UI, with
      transaction hashes and screenshots.
- [ ] Wrapper deposit and exercise work through the UI, and the pool readout is visible with
      its limitations.
- [ ] Playwright/browser E2E tests cover the main flows and pass in CI.
- [ ] A new vault-backed series completes create → fund → purchase → maturity → `expire()`
      → `finalize()` → `closeTrove()`.
- [ ] The close arithmetic reconciles with on-chain balances.
- [ ] At least three independent testnet wallets complete the required actions, or the
      workstream is explicitly marked partial with the actual number and reason.
- [ ] A scoped independent review is published, high/medium findings are remediated, and
      the remaining findings are disclosed.
- [ ] Monitoring and an incident/close runbook are in place.
- [ ] README, submission, deployment record, validation status, threat model, test output,
      and web-app docs match the new state.
- [ ] No claim of audit, organic demand, mainnet readiness, or native/ERC-20 BTC conversion
      has been added.

Not required for Wave 2 completion:

- Mainnet deployment.
- A full security audit (only a scoped independent review is promised).
- Organic liquidity or a market maker.
- Premium discovery/auction.
- MEZO governance-token integration.
- Closing the existing main trove if it remains unfunded; the new cohort is the close proof.

---

## 8. What Wave 2 will not claim

Do **not** say any of the following about Wave 2, even after the work above:

- “Roster is audited” unless an actual audit is completed and published.
- “Roster is production-ready” or “safe for real funds.” Wave 2 is testnet-only.
- “The main trove was closed” unless it actually was.
- “The main series expired/finalized” before `2026-11-24` or before the transactions exist.
- “There is organic demand.” Independent testnet users are not customers.
- “The premium is market-discovered.” The writer still sets the premium.
- “The wrapper/MUSD pool is deep, organic, or a Roster market.” It is a thin,
  deployer-seeded third-party pool.
- “The wrapper is collateral or redeemable for native BTC/series collateral.” It is not.
- “The wrapper can settle after expiry.” It cannot.
- “The pool can exercise its own positions.” It cannot.
- “Native BTC and ERC-20 BTC are interchangeable through Roster.” They are separate
  accounting paths.
- “The app supports the wrapper” before the Wave 2 UI is actually shipped and tested.
- “The project uses MEZO.” It does not.
- “Roster is a Track 2 project.” It is Track 1 DeFi infrastructure.

---

## 9. Risks, dependencies, and mitigations

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Main series expires outside Wave 2 | Cannot use it for the lifecycle proof | Use a new short-dated vault-backed cohort; report the main series separately |
| New trove close is still underfunded | Would repeat the main-vault failure | Size the trove small enough that the close repayment is fundable; preflight the math; if still short, publish the shortfall and do not claim a close |
| Testnet MUSD/BTC availability | Blocks funding and settlement | Source before deployment; use small amounts; document every funding transfer |
| Wallet E2E is difficult in CI | Automated tests may diverge from real wallet behavior | Use a deterministic local fixture for CI; perform a separate manual live-wallet pass |
| Mezo BTC token cannot be forked locally | Local full-stack simulation is blocked | Keep live testnet evidence for the BTC path; use mocks only for UI E2E |
| Independent testers do not materialize | External-validation workstream fails | Recruit early; report the actual number; do not substitute generated accounts |
| Security review finds serious issues | Timeline and scope may change | Gate completion on high/medium remediation; publish findings; do not hide them |
| Pool remains thin and deployer-seeded | Users may mistake it for liquidity | Label it everywhere; do not add a Roster incentive; do not market it as a market |
| App introduces misleading wrapper UX | Could imply post-expiry redemption | Whole-lot and expiry warnings; disable actions when `isLive() == false`; link to limitations |
| Testnet RPC instability | Missing logs or failed reads | 9,000-block log windows; receipt polling; `--json` checks; retry with confirmation |
| Scope creep into mainnet/audit | Overpromising | Keep Wave 2 testnet-only; list mainnet and audit as post-Wave-2 gates |

---

## 10. How to verify the current submission

### 10.1 Chain reads

```bash
RPC=https://rpc.test.mezo.org

cast chain-id --rpc-url "$RPC"

# Main series
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "active_lots()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "collateral_balance_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "expired()(bool)" --rpc-url "$RPC"

# Wrapper and pool
cast call 0x4726a021ec380a755EBE883BEb800A5d06723E41 \
  "totalSupply()(uint256)" --rpc-url "$RPC"
cast call 0x4726a021ec380a755EBE883BEb800A5d06723E41 \
  "underlyingLots()(uint256)" --rpc-url "$RPC"
cast call 0xED305fEF4c11f95dAe1d144e78B2B62be50965F2 \
  "getReserves()(uint256,uint256,uint256)" --rpc-url "$RPC"

# Trove
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "troveInfo()(uint256,uint256,uint256,uint256,uint8)" --rpc-url "$RPC"
```

### 10.2 Tests and build

```bash
forge fmt --check
forge build
forge test -vvv
FOUNDRY_PROFILE=ci forge test
python3 scripts/static_validate.py
cd app && npm run build
```

### 10.3 Evidence documents

- [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md) — addresses, hashes, terms, snapshot.
- [`COMPOSABILITY.md`](COMPOSABILITY.md) — wrapper, pool, external-account ledger.
- [`VALIDATION_STATUS.md`](VALIDATION_STATUS.md) — what is validated and what is not.
- [`TEST_OUTPUT.txt`](TEST_OUTPUT.txt) — recorded test/build/live/browser output.
- [`TEST_PLAN.md`](TEST_PLAN.md) — test design and coverage.
- [`THREAT_MODEL.md`](THREAT_MODEL.md) — threat model and assumptions.
- [`WEB_APP.md`](WEB_APP.md) — app inventory and wallet-test caveat.
- [`deployment.json`](deployment.json) — machine-readable state.

### 10.4 Explorer entry points

- Main series: `https://explorer.test.mezo.org/address/0xC23167867baAF830D586598DE0634E26fD895b92`
- Vault: `https://explorer.test.mezo.org/address/0x214e2316EAEeE24c1dc5d8433329fFC7544DA331`
- Wrapper: `https://explorer.test.mezo.org/address/0x4726a021ec380a755EBE883BEb800A5d06723E41`
- Pool: `https://explorer.test.mezo.org/address/0xED305fEF4c11f95dAe1d144e78B2B62be50965F2`
- External exercise: `https://explorer.test.mezo.org/tx/0xf9376c6eafd76fbaeb96b1536814fad60c84e9f888b9aecae2af6c5e7fd4bab7`

---

## 11. Copy-ready resubmission answers

### 11.1 One-line description

> Roster is a fixed-series BTC put and MUSD credit mechanism on Mezo, with a trove-backed
> writer, physical ERC-20 BTC exercise, a secondary ask book, and a standard wrapper that
> lets actual positions be held and traded on a Mezo Pools venue and settled through the
> series.

### 11.2 What changed since Wave 1?

> Since Wave 1, Roster added a live external composability path over actual positions: a
> standard 18-decimal `RosterPositionWrapper` holds main-series lots 1:1, a Mezo Pools
> wrapper/MUSD pool holds the wrapper, and a separate generated account with no direct
> series position acquired wrapper tokens through the Mezo router and exercised one lot,
> delivering ERC-20 BTC for the fixed MUSD payout. The suite grew from 82 to 91 tests,
> including nine wrapper tests, and the docs and disclosures were expanded. The core
> series, vault, order book, and terms did not change. The main trove is still open, the
> main series has not matured, there is no audit, no organic demand, and no wallet
> transaction has been sent through the app.

### 11.3 What will Wave 2 deliver?

> Wave 2 will make Roster a complete, externally validated testnet product. It will:
> (1) host the five-page app and add wrapper/pool views and wrapper actions, with a live
> wallet pass and automated browser E2E; (2) deploy a new small, short-dated vault-backed
> series and demonstrate `expire()`, `finalize()`, and `closeTrove()` end-to-end, including
> reconciled close math; (3) recruit at least three independent testnet wallets and publish
> their transactions and feedback without calling it demand; and (4) commission a scoped
> independent review, fix high/medium findings, and add monitoring and a close runbook.
> Wave 2 remains testnet-only. It does not claim mainnet readiness, an audit, organic
> liquidity, or a close of the existing underfunded main trove.

### 11.4 Milestones

> Days 1–30: hosted app, live wallet purchase/exercise, wrapper/pool UI, automated E2E.
> Days 20–60: new right-sized vault-backed series through expiry, `finalize()`, and
> `closeTrove()`. Days 35–75: three independent testnet users, scoped security review,
> remediation, monitoring, and runbook. Days 70–90: refreshed docs, demo video, and final
> submission evidence. Main-series expiry is captured separately if it falls inside the
> window.

### 11.5 Why Track 1?

> Roster is DeFi infrastructure: it issues a BTC put series against MUSD credit, provides a
> secondary ask book for those positions, and exposes actual positions to an external AMM
> through a standard wrapper. It is not a discovery tool, bot, wallet, or distribution
> product, so Track 2 is not a genuine fit.

### 11.6 Strongest accurate summary

> Roster has a working Mezo testnet mechanism with real MUSD, a real trove, a live secondary
> book, and a live Mezo Pools market over actual wrapped series positions. Wave 1 proved
> issuance, purchase, fill, exercise, premium, and expiry. The post-Wave-1 work proved
> external settlement of an actual position. Wave 2 is the remaining testnet validation:
> wallet-complete app, full vault close lifecycle, independent users, and a scoped security
> review. It is not audited, has no organic demand, has not closed the main trove, and has
> not reached mainnet.

---

## 12. Related documents

| Document | Purpose |
| --- | --- |
| [`../README.md`](../README.md) | Canonical project, deployment, and evidence record |
| [`SUBMISSION.md`](SUBMISSION.md) | Wave 1 submission narrative |
| [`COMPOSABILITY.md`](COMPOSABILITY.md) | Wrapper, Mezo Pools pool, and external-account ledger |
| [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md) | Addresses, hashes, terms, and snapshots |
| [`VALIDATION_STATUS.md`](VALIDATION_STATUS.md) | Validation evidence and safe/unsafe claims |
| [`TEST_PLAN.md`](TEST_PLAN.md) | Test design and coverage |
| [`TEST_OUTPUT.txt`](TEST_OUTPUT.txt) | Recorded test/build/live/browser output |
| [`THREAT_MODEL.md`](THREAT_MODEL.md) | Threat model and assumptions |
| [`WEB_APP.md`](WEB_APP.md) | Full web-app inventory and wallet-test caveat |
| [`deployment.json`](deployment.json) | Machine-readable deployment state |

---

### Final note

The Wave 2 resubmission should be judged on a narrow claim:

> Roster already demonstrates the mechanism and an external settlement path with real
> Mezo assets. Wave 2 is funded work to finish the missing testnet validation and publish
> the evidence — not a promise of mainnet readiness, organic demand, or a risk-free
> product.

Anything stronger is not supported by the current chain state or this repository.
