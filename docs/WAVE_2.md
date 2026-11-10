# Wave 2 Resubmission — Roster

**Project:** Roster Finance
**Track:** Track 1 — DeFi only
**Category:** Bitcoin options and credit
**Network:** Mezo testnet, chain ID `31611`
**Wave 1 baseline:** commit `0ff72da` (core stack and five-page app; 82/82 tests; no
external composability path)
**Wave 1.5 (post-Wave-1 composability):** commit `b6ecf8d` (wrapper, Mezo Pools
integration, 91/91 tests)
**Wave 2 code changes:** this branch — protocol fee model, Recovery Mode guard,
trove lifecycle coverage, 102/102 tests

> This document answers the two questions a Wave 2 resubmission must answer without
> ambiguity:
>
> 1. **What changed since Wave 1?**
> 2. **What exactly will be delivered in Wave 2?**

---

## 1. Wave 2 at a glance

| Requirement                                             | Status                                                                                                            |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Full trove lifecycle on-chain (repay, close, claim)     | Tested; `repay`, `closeTrove`, `claimCollateral` already in vault — 23 → 30 unit tests                            |
| Liquidation and Recovery Mode risk handling             | `RecoveryModeActive` guard on `openAndFund` and `borrowMore`; `claimCollateral` for surplus; 7 new tests          |
| Revenue model — protocol fee on premiums                | `feeBps` + `feeRecipient` on every series; fee forwarded immediately at purchase; 5 new tests                     |
| Revenue model — protocol fill fee on order-book fills   | `fillFeeBps` + `feeRecipient` on order book; accrues in contract; `sweepFees()` permissionless flush; 4 new tests |
| Wallet write flows from app (buy, exercise, list, fill) | Pending: requires live app MetaMask integration and on-chain evidence                                             |
| Contract verification on Mezo explorer                  | Pending: requires `forge verify-contract` with new constructor args                                               |
| Independent outside users                               | Pending: requires recruitment and funded testnet accounts                                                         |
| Video ≤ 2 minutes                                       | Pending: re-cut from current 3:15                                                                                 |
| 102/102 tests                                           | Done                                                                                                              |

---

## 2. What changed since Wave 1

### 2.1 Protocol fee on premiums (`RosterBtcPutSeries`)

Every series now carries two immutable fee fields set at deployment:

```
feeRecipient  address  — receives fees immediately at purchase
feeBps        uint256  — basis points on the buyer premium (max 500 = 5%)
```

The buyer pays `premium + fee` in one pull; the fee is forwarded to `feeRecipient`
in the same transaction and never touches `collateral_balance_raw` or
`premium_balance_raw`. The reserve backing active positions is unchanged.

```
total_fees_collected_raw  uint256  — cumulative fees forwarded (audit trail)
```

Zero `feeBps` is valid and produces no fee. The 5% hard cap is enforced at
construction via `MAX_FEE_BPS = 500` and `InvalidFeeBps` error.

### 2.2 Protocol fill fee on order-book fills (`RosterOrderBook`)

The order book now carries:

```
fillFeeBps    uint256  — basis points on the gross fill cost (max 500 = 5%)
feeRecipient  address  — receives fees when sweepFees() is called
accruedFees   uint256  — running balance of unclaimed fill fees
```

On each `fill()`:

```
grossCost        = lots × pricePerLot          (what buyer pays)
feeCharged       = grossCost × fillFeeBps / 10_000
sellerProceeds   = grossCost - feeCharged      (what seller receives)
```

The fee accrues in the contract until anyone calls `sweepFees()`, which flushes
the full balance to `feeRecipient`. This keeps fill gas predictable. Zero
`fillFeeBps` produces no accrual and `sweepFees()` reverts with `NothingToSweep`.

The `RosterSeriesFactory` similarly carries `feeRecipient` and `feeBps` at the
factory level and passes them through to every series it creates, so a single
factory deployment enforces a consistent fee policy across all series.

### 2.3 Recovery Mode guard (`RosterTroveWriter`)

The trove vault is long BTC through the trove and short puts through the series.
If Mezo enters Recovery Mode (system TCR < CCR = 150%), opening new troves or
drawing more MUSD would deepen the system crisis. The vault now checks:

```solidity
_requireNotRecoveryMode()  // calls troveManager.checkRecoveryMode(price)
```

before `openAndFund` and `borrowMore`. Both revert with `RecoveryModeActive(tcr)`
if the system is stressed. Operations that improve or preserve the system's health
— `repay`, `addCollateral`, `closeTrove` — are explicitly not gated.

Two new view helpers surface the state to the app and monitoring:

```solidity
isInRecoveryMode() external view returns (bool)
systemTCR()        external view returns (uint256)
```

The `ITroveManager` interface was extended with `getTCR(uint256)` and
`checkRecoveryMode(uint256)` to match Mezo's live contract surface.

### 2.4 `ITroveManager` interface extension

```solidity
function getTCR(uint256 price) external view returns (uint256);
function checkRecoveryMode(uint256 price) external view returns (bool);
```

These are live functions on Mezo's deployed `TroveManager`. The vault and the
deployment script interface (`IMezoTroveManagerStack`) both declare them.

### 2.5 Test coverage: 86 → 102 tests

| Suite                       | Wave 1.5 | Wave 2  | New                                                                                                       |
| --------------------------- | -------- | ------- | --------------------------------------------------------------------------------------------------------- |
| `RosterBtcPutSeriesTest`    | 36       | 41      | 5 (fee: collection, zero-fee, cap, reserve invariant, solvency)                                           |
| `RosterOrderBookTest`       | 13       | 17      | 4 (fill fee, sweep, empty sweep, zero fee)                                                                |
| `RosterTroveWriterTest`     | 23       | 30      | 7 (Recovery Mode blocks open/borrow, allows repay/addColl/close, view helpers, liquidation surplus claim) |
| `RosterSeriesFactoryTest`   | 4        | 4       | —                                                                                                         |
| `RosterPositionWrapperTest` | 9        | 9       | —                                                                                                         |
| `SeriesInvariantTest`       | 1        | 1       | —                                                                                                         |
| **Total**                   | **86**   | **102** | **16**                                                                                                    |

The `SeriesInvariant` fuzz suite (256 runs × 64 depth) passes unchanged.

### 2.6 Updated `MockTroveSystem` in tests

`MockTroveSystem` gained `setRecoveryMode(bool)` and implements
`getTCR(uint256)` / `checkRecoveryMode(uint256)` to allow deterministic testing
of the Recovery Mode guard without network calls.

### 2.7 Deployment script updates

Both `script/DeployStack.s.sol` and `script/DeploySeries.s.sol` read three new
env vars (`FEE_RECIPIENT_ADDRESS`, `FEE_BPS`, `FILL_FEE_BPS`) and pass them to
the factory and order book constructors. `.env.example` documents the new vars.

---

## 3. What Wave 2 still requires (on-chain / operational)

These items are code-ready but require live testnet execution:

### 3.1 Full trove lifecycle on-chain

The vault already implements `repay`, `closeTrove`, and `claimCollateral`. Wave 2
will deploy a small, deliberately fundable lifecycle series (e.g. 5 MUSD deposit,
50 MUSD debt) and broadcast each step:

| Step                                     | Method                  | Evidence    |
| ---------------------------------------- | ----------------------- | ----------- |
| Open trove + fund series                 | `openAndFund`           | existing tx |
| Buy puts                                 | `series.purchase`       | existing tx |
| Repay partial debt                       | `vault.repay`           | new tx      |
| Close trove                              | `vault.closeTrove`      | new tx      |
| Claim expiry release                     | `vault.finalize`        | new tx      |
| Claim collateral surplus (if applicable) | `vault.claimCollateral` | new tx      |

### 3.2 Recovery Mode evidence

The writer must demonstrate awareness of Recovery Mode in the submission video:
show `isInRecoveryMode()` returning false in normal operation, and explain that
`openAndFund` and `borrowMore` are blocked when it returns true. A testnet
simulation is acceptable if Recovery Mode is not live during the submission window.

### 3.3 Wallet write flows through the app

The five-page app needs MetaMask wallet connection and transaction signing for:

- Primary purchase (`buy` page)
- Exercise (`vault` page)
- List and fill (`trade` page)

Each flow needs an on-chain receipt with status 1 sent from a user's wallet
(not a script). Screenshots or screen recordings showing MetaMask confirmation
dialogs count as evidence.

### 3.4 Contract verification on Mezo explorer

Each new deployment must be verified with:

```bash
forge verify-contract <address> src/RosterBtcPutSeries.sol:RosterBtcPutSeries \
  --constructor-args $(cast abi-encode "constructor(...)" ...) \
  --rpc-url $MEZO_TESTNET_RPC_URL \
  --etherscan-api-key $MEZO_EXPLORER_API_KEY
```

The explorer must show source code and the ABI with `feeRecipient`, `feeBps`,
`fillFeeBps`, `accruedFees`, `sweepFees`, `isInRecoveryMode`, and `systemTCR`.

### 3.5 Independent outside users

At least three accounts not controlled by the deployer must:

- Purchase position lots through the app UI (not a script)
- Exercise or list at least one lot each

Evidence: Mezo explorer transaction links showing different `from` addresses.

### 3.6 Video re-cut to ≤ 2 minutes

The current video is 3:15. The re-cut must cover:

1. App wallet connection and a live purchase (30 s)
2. Trove lifecycle — open, repay, close — narrated fast (40 s)
3. Recovery Mode guard: show the read-only `isInRecoveryMode()` view (10 s)
4. Protocol fee: show a purchase receipt with fee forwarded to `feeRecipient` (20 s)
5. Secondary market: list, fill, sweep fees (20 s)

---

## 4. What Wave 2 will not claim

- Audit. No professional audit has been performed.
- Organic demand. Test participants are funded by the deployer.
- Mainnet readiness. This is a testnet demonstration only.
- MEZO governance-token usage. The integration uses MUSD, Mezo credit infrastructure,
  Mezo ERC-20 BTC, and Mezo Pools only.
- Automated liquidation or redemption bots.

---

## 5. Related documents

- [`SUBMISSION.md`](SUBMISSION.md) — Wave 1 narrative
- [`COMPOSABILITY.md`](COMPOSABILITY.md) — Mezo Pools composability record
- [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md) — live contract addresses
- [`THREAT_MODEL.md`](THREAT_MODEL.md) — security assumptions
- [`TEST_PLAN.md`](TEST_PLAN.md) — test strategy
