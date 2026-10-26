# Test Plan and Coverage

**Last executed:** 2026-10-26
**Result:** 91/91 tests pass in both the default and CI profiles
**Toolchain:** Foundry 1.7.1, solc 0.8.24, `via_ir = true`, optimizer 200 runs,
EVM `london`

This document describes what the test suite actually covers, how it is executed, and
what it does not cover. It replaces the earlier version that incorrectly said Foundry
was unavailable and that no test result was claimed. Foundry is installed, the suite
runs, and the live deployment has been separately validated.

See [`TEST_OUTPUT.txt`](TEST_OUTPUT.txt) for the recorded command output and
[`VALIDATION_STATUS.md`](VALIDATION_STATUS.md) for live-chain validation.

---

## 1. Scope

The suite covers five contracts and their interactions:

| Contract | Suite | Tests |
| --- | --- | --- |
| `RosterBtcPutSeries` | `RosterBtcPutSeriesTest` | 36 |
| `RosterTroveWriter` | `RosterTroveWriterTest` | 23 |
| `RosterOrderBook` | `RosterOrderBookTest` | 13 |
| `RosterSeriesFactory` | `RosterSeriesFactoryTest` | 4 |
| `RosterPositionWrapper` | `RosterPositionWrapperTest` | 9 |
| Invariants | `SeriesInvariantTest` | 6 |
| **Total** | | **91** |

The suite uses local mocks for MUSD and ERC-20 BTC. It does not execute against a
deployed Mezo fork. The live Mezo path is validated through testnet transactions; see
the deployment record.

---

## 2. Profiles and parameters

```toml
[profile.default]
solc_version = "0.8.24"
evm_version = "london"
optimizer = true
optimizer_runs = 200
via_ir = true

[profile.default.fuzz]
runs = 512

[profile.default.invariant]
runs = 256
depth = 64
fail_on_revert = false

[profile.ci.fuzz]
runs = 5000
max_test_rejects = 100000

[profile.ci.invariant]
runs = 512
depth = 100
fail_on_revert = false
```

The default profile is fast enough for iteration. The CI profile is the larger fuzz
and invariant campaign.

---

## 3. Execution

```bash
# Formatting
forge fmt --check

# Build
forge build

# Default suite
forge test -vvv

# Larger CI campaign
FOUNDRY_PROFILE=ci forge test

# Invariants only
forge test --match-contract SeriesInvariantTest -vvv

# List every test
forge test --list
```

Expected result at the recorded revision:

```text
Ran 6 test suites: 91 tests passed, 0 failed, 0 skipped
```

---

## 4. Core series coverage — `RosterBtcPutSeriesTest` (36)

### 4.1 Construction and metadata

- `test_constructor_invalid_params` — zero addresses, identical assets, invalid expiry,
  non-divisible strike, zero premium.
- `test_constructor_zero_premium_reverts`.
- `test_constructor_wrong_btc_decimals_reverts`.
- `test_erc20_interface_and_totalSupply_pre_post_expiry` — `name`, `symbol`,
  `decimals() == 0`, supply semantics.
- `test_direct_musd_transfer_is_uncredited` — unsolicited MUSD is not treated as a
  deposit.

### 4.2 Deposits and accounting

- `test_deposit_updates_state` — deposit, collateral, excess, and audit counters.
- `test_deposit_writer_only` — non-writer deposit is rejected.
- `test_solvency_after_every_action` — contract MUSD covers collateral plus premium
  liabilities after a sequence of operations.
- `test_fee_on_transfer_musd_is_rejected_atomically` — exact-transfer enforcement and
  rollback.
- `test_invariant_pre_and_post_expiry` — collateral split and reserve identity before
  and after expiry.
- `test_expiry_release_audit_identity` — deposits minus payouts minus release equals
  remaining collateral.

### 4.3 Purchases

- `test_purchase_any_nonwriter` — a non-writer buyer receives the correct lots and the
  writer cannot buy.
- `test_purchase_writer_reverts`.
- `test_purchase_capacity` — purchases cannot exceed unreserved collateral.
- `test_zero_quantities_revert` — zero deposit/purchase/exercise/transfer quantities
  are rejected where applicable.

### 4.4 Exercise

- `test_exercise_exact_payout_no_rounding` — 80,000 strike yields exactly 0.08 MUSD per
  lot.
- `test_exercise_partial`.
- `test_exercise_self_only` — only the position holder can exercise their own tokens.
- `test_exercise_writer_reverts`.
- `test_exercise_insufficient_btc_reverts`.
- `test_exercise_insufficient_allowance_reverts`.
- `test_exercise_after_expiry_reverts`.

### 4.5 Transfers and approvals

- `test_transferFrom_without_allowance_reverts`.
- `test_transfer_to_writer_blocked`.
- `test_transferFrom_to_writer_blocked`.
- `test_transfer_to_self_contract_reverts`.
- `test_transfer_at_maturity_reverts`.
- `test_transfer_after_finalization_reverts`.
- Approval semantics are covered inside the ERC-20 interface and transfer tests.

### 4.6 Expiry and premium

- `test_expire_permissionless_idempotent` — anyone can expire, and repeated calls do not
  release additional collateral.
- `test_expire_releases_all_collateral`.
- `test_limbo_state` — after maturity but before `expire()`, purchases/exercises/
  transfers are frozen while supply remains pre-expiry.
- `test_withdraw_premium_writer_only`.
- `test_solvency_after_every_action`.

### 4.7 Reentrancy and adversarial tokens

- `test_reentrancy_callback_blocked_by_guard_nonzero_allowance`.
- `test_reentrancy_callback_blocked_by_guard_zero_allowance`.
- `test_reentrancy_callback_bubbled_reverts_outer`.
- `test_reentrancy_with_adversarial_token`.
- `test_fee_on_transfer_musd_is_rejected_atomically`.

These verify the shared reentrancy guard, callback behavior, and atomic rollback when
an adversarial token re-enters or reverts.

---

## 5. Factory coverage — `RosterSeriesFactoryTest` (4)

- `test_factory_creates_registers_and_exposes_terms` — creation, registration,
  `seriesCount`, `seriesAt`, `allSeries`, assets, strike, premium, expiry, name,
  symbol.
- `test_factory_allows_multiple_writers_and_series` — multiple independent writers and
  series can coexist.
- `test_factory_rejects_bad_asset_pair` — identical or invalid assets are rejected by
  the series constructor.
- `test_factory_rejects_invalid_constructor_parameters` — zero addresses and bad
  constructor inputs.

The factory is permissionless: it has no owner, pause, or allowlist. Registration only
means the order book will accept the series; it is not a quality endorsement.

---

## 6. Order-book coverage — `RosterOrderBookTest` (13)

- `test_list_and_partial_fill_moves_tokens_and_musd` — escrow, partial fill, direct
  MUSD payment to seller, position-token movement.
- `test_full_fill_deactivates_listing`.
- `test_partial_fill_then_cancel_returns_remainder`.
- `test_cancel_only_seller`.
- `test_list_requires_position_approval`.
- `test_fill_requires_musd_allowance`.
- `test_invalid_listing_inputs_revert` — zero lots, zero price, malformed input.
- `test_unknown_and_overfilled_listings_revert`.
- `test_list_after_maturity_reverts`.
- `test_fill_and_cancel_after_maturity_revert`.
- `test_order_book_rejects_unregistered_series`.
- `test_order_book_rejects_mismatched_musd_series`.
- `test_order_book_constructor_rejects_factory_with_different_musd`.

The book is ask-only. It has no bids, matching engine, fees, keeper, or owner.

---

## 7. Trove writer coverage — `RosterTroveWriterTest` (23)

### 7.1 Lifecycle and authorization

- `test_open_and_fund_creates_separate_series_and_trove`.
- `test_open_and_fund_only_owner`.
- `test_open_requires_bound_series_and_bind_validation`.
- `test_open_twice_reverts`.
- `test_open_rejects_bad_deposit_and_zero_collateral`.
- `test_add_and_borrow_require_active_trove`.
- `test_set_min_icr_and_ownership`.
- `test_receive_rejects_unexpected_native_sender`.

### 7.2 Collateral, borrowing, and repayment

- `test_add_and_withdraw_collateral`.
- `test_borrow_more_and_deposit_to_series`.
- `test_borrow_more_icr_guard`.
- `test_partial_repay`.
- `test_icr_guard_reverts_unsafe_open_atomically`.

### 7.3 Close and expiry

- `test_close_trove_repays_only_debt_minus_gas_compensation`.
- `test_close_trove_updates_interest_before_top_up`.
- `test_close_trove_requires_external_musd_for_borrowing_fee`.
- `test_close_trove_preserves_reserved_expiry_proceeds`.
- `test_close_trove_requires_musd_and_active_trove`.
- `test_third_party_expire_then_finalize_forwards_once`.
- `test_withdraw_premium_and_finalize`.

### 7.4 Surplus, BTC proceeds, and reads

- `test_claim_collateral_surplus_from_pool`.
- `test_withdraw_btc_exercise_proceeds`.
- `test_trove_info_and_series_state`.

The close tests model Mezo's observed 0.1% borrowing fee: a 2,000 MUSD borrow creates
2,202 MUSD of debt, and close repayment is 2,002 MUSD after excluding the 200 MUSD gas
compensation. The vault must gross-fund 1,502 MUSD when 1,500 MUSD is reserved for an
expired series; `finalize()` returns the 1,500 MUSD, so the owner's net cost is the
2 MUSD fee. The fee is governance-configurable, so a live deployment must read it at
execution time.

---

## 8. Wrapper coverage — `RosterPositionWrapperTest` (9)

`RosterPositionWrapperTest` uses a local series and tokens. It verifies the adapter that
exposes series lots to external ERC-20 venues.

- `test_deposit_and_withdraw_round_trip` — deposit lots, mint `lots * 1e18`, withdraw, and
  return the exact series position tokens.
- `test_deposit_requires_series_approval` — deposit reverts without a series allowance.
- `test_exercise_requires_btc_approval` — exercise reverts without an ERC-20 BTC allowance.
- `test_exercise_via_wrapper` — exercise burns whole lots, pulls `lots * 1e12` ERC-20 BTC,
  calls the series, and forwards the exact MUSD payout.
- `test_expiry_blocks_settlement_but_not_wrapper_transfers` — after expiry, `deposit`,
  `withdraw`, and `exercise` revert while wrapper transfers still succeed.
- `test_non_multiple_and_zero_amounts_revert` — zero and fractional wrapper amounts cannot
  be withdrawn or exercised.
- `test_transfer_and_allowance` — wrapper units are standard ERC-20 balances with working
  approvals and `transferFrom`.
- `test_underlying_and_supply_stay_in_sync` — `totalSupply == underlyingLots * 1e18`
  through deposit, withdraw, and exercise.
- `test_withdraw_to_writer_reverts` — the wrapper cannot return series tokens to the
  writer, inheriting the series transfer restriction.

The wrapper tests do **not** run against the live Mezo Pools factory, router, or pool.
That integration was demonstrated on testnet and is recorded in
[`COMPOSABILITY.md`](COMPOSABILITY.md).

---

## 9. Invariants — `SeriesInvariantTest` (6)

`SeriesInvariant.t.sol` defines six properties:

1. **`invariant_collateral_split`**
   ```text
   collateral_balance_raw == reserved_raw + excess_raw
   ```
2. **`invariant_reserve_matches_active_lots`**
   ```text
   reserved_raw == active_lots * strike_per_lot_raw
   ```
3. **`invariant_supply_equals_active_lots_until_finalization`**
   ```text
   totalSupply() == active_lots   (before expiry release)
   ```
4. **`invariant_finalized_counters_and_supply`**
   ```text
   after expire(): collateral == reserved == excess == active_lots == 0
   supply equals tracked holder balances and remains frozen
   ```
5. **`invariant_audit_identity`**
   ```text
   total_deposited - total_payouts - expiry_release == collateral_balance
   ```
6. **`invariant_musd_solvency_at_action_boundaries`**
   ```text
   musd.balanceOf(series) >= collateral_balance_raw + premium_balance_raw
   ```

### 9.1 Handler actions

The invariant handler fuzzes:

- writer deposit;
- purchase by a registered actor;
- exercise by a registered actor;
- position transfer;
- approval;
- `transferFrom`;
- premium withdrawal;
- maturity;
- finalization.

Token recipients are constrained to the fixed actor set, so the supply/balance sum is
closed over all possible holders in the campaign. Expected reverts are caught and
treated as low-level call failures; the invariants are evaluated at successful action
boundaries.

`fail_on_revert = false` is deliberate: the handler uses low-level calls and expects
invalid actions to revert. This does not weaken the post-condition checks on successful
actions.

---

## 10. What is validated on-chain

The test plan is not the only evidence. The live deployment separately validates:

- factory deployment and two-series registration;
- series creation with the vault as writer;
- vault binding;
- a real Mezo trove open with 0.043 native BTC;
- a 2,000 MUSD borrow and 1,500 MUSD series deposit;
- a separate buyer purchase of 100 lots;
- a 50-lot order-book listing and 25-lot fill;
- an exercise of 25 lots for 2 MUSD;
- a 0.1 MUSD premium withdrawal through the vault;
- a demo expiry release of 20 MUSD;
- frozen position supply after expiry;
- a wrapper holding 19 actual main-series lots at 1:1 accounting;
- a Mezo Pools wrapper/MUSD pool created and seeded with 15 lots and 0.03 MUSD;
- a generated external account swapping MUSD for wrapper and exercising one lot for
  0.08 MUSD.

See [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md) for hashes and the current snapshot,
and [`COMPOSABILITY.md`](COMPOSABILITY.md) for the external-integration ledger.

---

## 11. What is not covered

- **No audit or formal verification.** Tests cannot prove absence of all
  vulnerabilities.
- **No local Mezo fork execution.** The Mezo ERC-20 BTC token's `decimals()` call
  reverts under local Foundry/revm forks (`EvmError: NotActivated`). The BTC path was
  validated on live testnet instead.
- **No local fork test of Mezo Pools.** The wrapper/MUSD pool, router, and swap path were
  demonstrated on testnet, not reproduced in Foundry.
- **Wrapper tests use local mocks.** They do not exercise adversarial AMM callbacks or a
  live pool trying to call `exercise()` (the AMM cannot).
- **No live liquidation or redemption simulation.**
- **No multi-block interest simulation against Mezo.** Interest is modeled in the
  close-path test but not fuzzed against live protocol state.
- **No MEZO governance-token behavior**, because none is integrated.
- **No load, griefing, MEV, or economic-security analysis.**
- **No order-book liquidity guarantee.** The tests prove mechanics, not demand.
- **No web-app end-to-end or wallet transaction tests.** The five-page app builds and
  has a read-only browser smoke pass with desktop/mobile screenshots; wallet integration
  and automated E2E remain outstanding.
- **No production-token adversarial suite** beyond local mocks.
- **No mainnet deployment.**

---

## 12. Pass criteria for future changes

Before treating a change as safe enough for another testnet deployment:

```bash
forge fmt --check
forge build
forge test -vvv
FOUNDRY_PROFILE=ci forge test
```

Additionally:

- all six invariants must hold;
- no new compiler errors;
- no test may be deleted to make the suite pass;
- any change to accounting, expiry, or vault close must add a targeted regression test;
- the live snapshot must be re-read after deployment;
- no key or `.env` may be committed;
- the README and docs must be updated with the new addresses and hashes.
