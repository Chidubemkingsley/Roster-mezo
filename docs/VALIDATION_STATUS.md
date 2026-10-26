# Validation Status

**Status as of 2026-10-26 10:15 UTC:** compiled, tested, deployed to Mezo testnet,
exercised through primary purchase, secondary fill, physical exercise, premium
withdrawal, and expiry release on a short-dated demo series. The main series remains
active. The trove remains open. A position wrapper is live over main-series lots, and a
deployer-seeded Mezo Pools wrapper/MUSD pool was used by a separate generated account to
acquire wrapper tokens and exercise one lot. The five-page web app passed a read-only
browser smoke test at desktop and mobile widths but does not surface the wrapper or pool.
No audit has been performed, and no wallet transaction has been sent through the UI.

The chain snapshot below is the **2026-10-26 10:15:56 UTC** snapshot (block 16,379,045).
Debt, interest, ICR, and balances move. The browser check on 2026-10-26 observed
approximately 156.4% ICR and 2,202.035 MUSD debt at its earlier block; those values are
historical. This file records what has actually been validated. It replaces the earlier
"compiled and tested locally; not yet deployed" status, which is no longer true.

Canonical sources:

- [`../README.md`](../README.md) — primary project record.
- [`DEPLOYMENT_RECORD.md`](DEPLOYMENT_RECORD.md) — addresses, hashes, terms, snapshot.
- [`COMPOSABILITY.md`](COMPOSABILITY.md) — wrapper, Mezo Pools, and external-account record.
- [`TEST_OUTPUT.txt`](TEST_OUTPUT.txt) — recorded command output.
- [`SUBMISSION.md`](SUBMISSION.md) — submission narrative.
- [`WEB_APP.md`](WEB_APP.md) — full web-app inventory.

---

## 1. Summary

| Area | Status | Evidence |
| --- | --- | --- |
| Formatting | Pass | `forge fmt --check` exit 0 |
| Compilation | Pass | `forge build`, lint warnings only |
| Default test suite | **91/91 pass** | `forge test -vvv` |
| CI test profile | **91/91 pass** | `FOUNDRY_PROFILE=ci forge test` |
| Static consistency checks | Pass | `python3 scripts/static_validate.py` |
| Mezo testnet deployment | **Live** | Six Roster contracts with code |
| Main series active | **Yes** | 74 active lots, 1,497.92 MUSD collateral |
| Primary purchase | **Live** | 100 lots purchased |
| Secondary listing/fill | **Live** | 50 listed, 25 filled |
| Physical exercise | **Live** | 26 lots for 2.08 MUSD total |
| Premium withdrawal | **Live** | 0.1 MUSD forwarded |
| Demo expiry release | **Live** | 20 MUSD released |
| Trove open | **Live** | 0.043 native BTC, ~2,202 MUSD debt |
| Trove close | **Not demonstrated** | MUSD shortfall |
| Main expiry/finalize | **Not reached** | 2026-11-24 |
| Position wrapper | **Live** | 19 lots / 19e18 supply, 1:1 backed |
| Wrapper/MUSD Mezo Pools pool | **Live, deployer-seeded** | 15-lot initial seed; external swap/exercise executed |
| External position composability | **Demonstrated** | Generated external account swapped and exercised 1 lot |
| Web app production build | **Pass** | Five-page Vite build |
| Web app read-only browser pass | **Pass** | Five pages, 1440px and 390px; screenshots in `docs/screenshots/`; predates wrapper/pool |
| Web app wallet transaction | **Not performed** | No wallet connected; no transaction through the UI |
| Web app wrapper/pool support | **Not implemented** | Verified via `cast` and explorer, not UI |
| Audit | **None** | Do not claim one |
| Organic demand | **None observed** | Buyer and external account are generated; pool is deployer-seeded |

---

## 2. Local validation

### 2.1 Toolchain

| Tool | Version / setting |
| --- | --- |
| Foundry | `1.7.1` |
| Solidity | `0.8.24` |
| EVM version | `london` |
| Optimizer | enabled, 200 runs |
| `via_ir` | `true` |
| Test dependency | no `forge-std`; local `Vm` interface only |

### 2.2 Formatting and build

```text
$ forge fmt --check
(no output; exit code 0)

$ forge build
Compiler run successful with warnings
build exit code 0
```

Warnings are Foundry lint warnings, primarily `block.timestamp` comparisons in
lifecycle checks and unchecked return values in test-only token calls. There are no
compiler errors.

### 2.3 Static consistency checks

```text
$ python3 scripts/static_validate.py
PASS: required files and relative imports resolve
PASS: 36 unique unit-test functions found
PASS: 6 unique invariant functions found
PASS: 9 unique wrapper-test functions found
PASS: required regression test names present
PASS: env keys are consistent across sample config and scripts
PASS: sample config defaults to the verified Mezo MUSD and ERC-20 BTC addresses
PASS: CI profile and compile/default/expanded test workflow are configured
PASS: deployment script contains chain, writer, code, and decimal preflight checks
PASS: wrapper source, wrapper test suite, and wrapper test count are present
PASS: documented strike/premium arithmetic is consistent
```

This is a static repository check only. It does not compile Solidity or execute EVM
tests. The GitHub Actions workflow at `.github/workflows/test.yml` runs `forge build`,
the default and CI test profiles, `forge fmt --check`, and this script. The workflow has
been observed passing on GitHub: run `40264693650`.

### 2.4 Default test profile

```text
$ forge test -vvv
Ran 4 tests for test/ProtocolExtensions.t.sol:RosterSeriesFactoryTest
Suite result: ok. 4 passed; 0 failed; 0 skipped

Ran 23 tests for test/ProtocolExtensions.t.sol:RosterTroveWriterTest
Suite result: ok. 23 passed; 0 failed; 0 skipped

Ran 36 tests for test/RosterBtcPutSeries.t.sol:RosterBtcPutSeriesTest
Suite result: ok. 36 passed; 0 failed; 0 skipped

Ran 13 tests for test/ProtocolExtensions.t.sol:RosterOrderBookTest
Suite result: ok. 13 passed; 0 failed; 0 skipped

Ran 9 tests for test/RosterPositionWrapper.t.sol:RosterPositionWrapperTest
Suite result: ok. 9 passed; 0 failed; 0 skipped

Ran 6 tests for test/SeriesInvariant.t.sol:SeriesInvariantTest
Suite result: ok. 6 passed; 0 failed; 0 skipped

Ran 6 test suites: 91 tests passed, 0 failed, 0 skipped
```

### 2.5 CI profile

```text
$ FOUNDRY_PROFILE=ci forge test
Ran 6 test suites: 91 tests passed, 0 failed, 0 skipped
```

Profile parameters:

```text
default fuzz runs:       512
default invariant runs:  256
default invariant depth: 64
CI fuzz runs:            5,000
CI invariant runs:       512
CI invariant depth:      100
fail_on_revert:          false
```

### 2.6 Test distribution

| Suite | Tests |
| --- | --- |
| `RosterBtcPutSeriesTest` | 36 |
| `RosterTroveWriterTest` | 23 |
| `RosterOrderBookTest` | 13 |
| `RosterSeriesFactoryTest` | 4 |
| `RosterPositionWrapperTest` | 9 |
| `SeriesInvariantTest` | 6 invariants |
| **Total** | **91** |

The extension suite also includes a large number of shared assertions inside those
tests. The count above is Foundry's test count, not a line-coverage number.

### 2.7 Invariant coverage

`SeriesInvariant.t.sol` supplies six properties:

1. `invariant_collateral_split` — collateral equals reserve plus excess.
2. `invariant_reserve_matches_active_lots` — reserve equals active lots times strike
   per lot.
3. `invariant_supply_equals_active_lots_until_finalization` — token supply equals live
   active lots before finalization.
4. `invariant_finalized_counters_and_supply` — after finalization, collateral and
   liability counters are zero; supply equals tracked balances and remains frozen.
5. `invariant_audit_identity` — deposits minus payouts minus expiry release equals
   remaining collateral.
6. `invariant_musd_solvency_at_action_boundaries` — after completed operations, MUSD
   covers recorded collateral and premium liabilities.

The handler fuzzes deposit, purchase, exercise, transfer, approval, `transferFrom`,
premium withdrawal, maturity, and finalization over a fixed actor set.

---

## 3. App validation

The web application is under [`../app`](../app). It is a static Vite + ethers
application with no backend.

### 3.1 Production build

The app is a five-page Vite build: landing, trade, secondary, vault, and activity. This
build was re-run after the disclosure-copy correction. The browser pass used the earlier
build (`index.html` 32.68 kB, `vault.html` 18.71 kB).

```text
$ cd app
$ npm run build

vite v7.3.7 building client environment for production...
✓ 156 modules transformed.
dist/activity.html              11.72 kB │ gzip:  3.41 kB
dist/secondary.html             14.60 kB │ gzip:  4.02 kB
dist/trade.html                 16.77 kB │ gzip:  4.29 kB
dist/vault.html                 18.75 kB │ gzip:  4.80 kB
dist/index.html                 32.82 kB │ gzip:  7.40 kB
dist/assets/main-uU5dssex.css   42.88 kB │ gzip:   8.54 kB
dist/assets/main-3VKCUrVU.js   303.59 kB │ gzip: 109.60 kB
✓ built in 1.56s
```

- `app/src/main.js` is page-aware via `body[data-page]` and populates only the sections
  needed by the current entry.
- The public Mezo RPC sends `access-control-allow-origin: *`, so browser reads are
  possible.
- The app is read-only without a wallet and uses the public RPC.

### 3.2 Read-only browser pass

On **2026-10-26** between approximately **01:15 and 01:25 UTC**, the production build was
served at `http://127.0.0.1:4173` and loaded in headless Chrome against the live Mezo RPC.
No wallet extension was installed and no transaction was signed or broadcast. **This pass
predates the wrapper and Mezo Pools work**; the live values below are historical.

| Check | Result |
| --- | --- |
| Five pages load | Pass: landing, trade, secondary, vault, activity |
| Uncaught app exceptions | None observed |
| Desktop 1440px | No horizontal overflow on any page |
| Mobile 390px emulation | No horizontal overflow; navigation visible on all pages |
| Live series data | 1,498 MUSD collateral, 75 active lots, 18,650 lots capacity |
| Trade quote | 100 lots → 0.1 MUSD premium, 8 MUSD payout, 0.0001 BTC |
| Trove read | 0.043 native BTC, approximately 2,202.035 MUSD debt, approximately 156.4% ICR |
| Vault read | 400 MUSD idle, 0 reserved, 0.000025 ERC-20 BTC, 0.1 MUSD premium forwarded |
| Secondary read | 1 listing, 25 lots at 0.002 MUSD/lot |
| Activity read | 13 decoded events, 8 contract cards |
| Vault close note | Required repayment plus an approximate 1,551.99 MUSD shortfall, counting the owner's MUSD |

The activity scanner uses 9,000-block `eth_getLogs` windows because Mezo's public RPC
rejects spans greater than 10,000 blocks. This was fixed and rechecked during the pass.

Screenshots are committed in [`screenshots/`](screenshots/):

- desktop: landing, full landing, trade, secondary, vault, activity;
- mobile: landing, trade, secondary, vault, activity.

### 3.3 What has not been checked

- No wallet transaction executed through the UI.
- No wallet signature, confirmation, or error state recorded.
- No automated end-to-end test suite for the app.
- No production hosting/deployment.
- The app does not surface the position wrapper or the Mezo Pools pool; that integration
  is verified with `cast` and the explorer.
- The browser pass predates the wrapper/pool and the latest series state (`74` lots,
  `1,497.92` MUSD); its `75` / `1,498` values are historical.

Do **not** describe the app as fully validated, wallet-tested, or finished. It is
implemented, builds, and has a read-only browser pass with screenshots; wallet
integration testing is still open.

---

## 4. Live Mezo testnet validation

### 4.1 Network and code

```text
chainId: 31611
RPC:     https://rpc.test.mezo.org
explorer: https://explorer.test.mezo.org
```

All six Roster-deployed addresses have non-empty bytecode:

| Contract | Address | Code |
| --- | --- | --- |
| Factory | `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F` | present |
| Order book | `0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25` | present |
| Trove vault | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` | present |
| Main series | `0xC23167867baAF830D586598DE0634E26fD895b92` | present |
| Demo series | `0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43` | present |
| Position wrapper | `0x4726a021ec380a755EBE883BEb800A5d06723E41` | present |

External Mezo Pools contracts used by the composability demo:

| Contract | Address | Code |
| --- | --- | --- |
| Basic PoolFactory | `0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A` | present |
| Basic Router | `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9` | present |
| Wrapper/MUSD pool | `0xED305fEF4c11f95dAe1d144e78B2B62be50965F2` | present; recognized by factory |

### 4.2 Assets and protocol addresses

- Chain ID: `31611`.
- MUSD: `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503`, `decimals() == 18`.
- Mezo ERC-20 BTC: `0x7b7C000000000000000000000000000000000000`,
  `decimals() == 18`.
- BorrowerOperations: `0xCdF7028ceAB81fA0C6971208e83fa7872994beE5`.
- TroveManager: `0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0`.
- PriceFeed: `0x86bCF0841622a5dAC14A313a15f96A95421b9366`.
- `MUSD_GAS_COMPENSATION()` returns `200e18`.
- `activePool()` returns `0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51`.
- `collSurplusPool()` returns `0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9`.
- `BorrowerOperations.getBorrowingFee(2,000e18)` returned `2e18` at the observed
  0.1% rate.
- PriceFeed `fetchPrice()` returned `80,327.18147e18` at the snapshot.
- Wrapper series: main series; `UNIT = 1e18`; `decimals() == 18`; `isLive() == true`.
- Wrapper `totalSupply() == 19e18`, `underlyingLots() == 19`.
- Mezo Pools `getPool(wrapper, MUSD, false)` returns the pool; `isPool(pool) == true`.
- Pool `token0 == MUSD`, `token1 == wrapper`, `stable == false`.
- `factory.allPoolsLength() == 38` at the snapshot.

The Mezo BTC token's `decimals()` call reverts under local Foundry/revm forks
(`EvmError: NotActivated`) while live `cast call` and transactions succeed. This is why
the final BTC path was validated on live testnet rather than by a local fork.

### 4.3 Deployment receipts

| Step | Transaction | Block | Status | Gas |
| --- | --- | --- | --- | --- |
| Deploy factory | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` | 16,359,308 | 1 | 2,500,000 |
| Deploy order book | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` | 16,359,315 | 1 | 2,500,000 |
| Deploy vault | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` | 16,359,322 | 1 | 2,500,000 |
| Create main series | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` | 16,359,328 | 1 | 5,000,000 |
| Bind vault | `0x475ac4a22814c979e736d56644e74e51c26028c0a76edc24a7a6596461162929` | 16,359,339 | 1 | 1,000,000 |
| Open trove + fund series | `0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3` | 16,359,352 | 1 | 5,000,000 |

### 4.4 Lifecycle receipts

| Step | Transaction | Block | Status |
| --- | --- | --- | --- |
| Withdraw 100 idle MUSD | `0x42382fc32c88c42c7f16d8039f8bd7ea677d9575492ea1dc26d9b98fa3e122b1` | 16,359,394 | 1 |
| Fund buyer 50 MUSD | `0xfcdedbe4097ef8c5b874ec18535cca1fae9846b5c75419a3a84d0fbbf82c3e8c` | 16,359,397 | 1 |
| Fund buyer 0.001 native gas BTC | `0x430568bca841c1f3cb0514b888831dbadc614256672cc2d4ab16b8a56db6007a` | 16,359,401 | 1 |
| Fund buyer 0.001 ERC-20 BTC | `0x7955e79d23d2490e008a4ef92dcf95cdc4db63b8780bc987c3dd62f470f9e54a` | 16,359,411 | 1 |
| Buyer approves MUSD | `0x21a70bfcc088cfbae46bba0e1856b28527f7a8e044fb8c78223562e27f229a63` | 16,359,416 | 1 |
| Buyer purchases 100 lots | `0xe267876b92c517fd0f12f52b8f3935f683bdca6eda8b832c1837bc11e14c7186` | 16,359,419 | 1 |
| Buyer approves position tokens | `0x49fd70c707bfc9590cb0afb4d4665b4677b3f2ee5b99b7bad1f1889f5d20a169` | 16,359,426 | 1 |
| Buyer lists 50 lots | `0x4c28017a4ca2f99c261b54ad30ecd4e21382b1e931eaae092fa76eda7ff3752e` | 16,359,433 | 1 |
| Deployer fills 25 lots | `0xd02d308ffd79ae818b78d88563189ffd9a3f88b72a13b0f93a73a4e1e5a2894e` | 16,359,445 | 1 |
| Buyer exercises 25 lots | `0x4230a5c81c8e351634306885098e5ad3765b27564c3d6ff08462815ce36f4991` | 16,359,457 | 1 |
| Vault withdraws premium | `0x5f82341945dba350e179211cabb5031228844eebfb328acb9112bee715ce8a50` | 16,359,469 | 1 |
| Demo created | `0xa7ff146b3ce49b46a8de4582c3826b320797b28d1e70fff7669530b4a10cabae` | 16,359,511 | 1 |
| Demo 20 MUSD approved | `0x4280f849273e419d07533f3d205047f264422805b0f511e7289e883eb464f0c4` | 16,359,517 | 1 |
| Demo 20 MUSD deposited | `0x89c016b7f19d87e89dba2ae8c3ecc4a5081b15a87d5ea681a5e328bea4275946` | 16,359,519 | 1 |
| Demo buyer approves 0.01 MUSD | `0x5f52c73be0789064f6894bbbcea0d18df19113c77e665ba84141880a62487aa9` | 16,359,524 | 1 |
| Demo buyer purchases 10 lots | `0xafa7a0e6227dd3d2d5eca8cd16e072a9443331a8d5f86cdc4480b568c6ba3815` | 16,359,527 | 1 |
| Demo `expire()` | `0xdc1b099d2f1a6256de62fdb28698167728416a9fb9df895ac19062d81eb5dd8d` | 16,359,832 | 1 |

### 4.5 Wrapper and external composability receipts

| Step | Transaction | Block | Status |
| --- | --- | --- | --- |
| Deploy wrapper | `0xe6e4b8c60ac5c8cd2c6f03ed541c82a5af8af42e0f45e1c3b272a956b5b297e7` | 16,378,802 | 1 |
| Approve + deposit first 10 lots | `0x4d2cf5c3eff0f19deb0d5f714f06a30dc4d9e32901502f8cd63019dde0608741`, `0x596fcecc54e2de075eb84efcb0a3f478d0e484344bde89878a8dc849e8087728` | 16,378,810 / 16,378,811 | 1 |
| Create Mezo Pools pool | `0xa5ef82750d15bfb89e2db3cd99e2f65c4c044131fbfce8a1c00aba99f470c3d8` | 16,378,881 | 1 |
| Add 5 lots + 0.01 MUSD | `0xcd453d9521f628f10b3c508a903754fcf06c3f05e30800d06a9b8413d0d39e6d` | 16,378,904 | 1 |
| Deposit 10 more lots + add 10 + 0.02 MUSD | `0x9da7db90d7496b5c948840a2fbdf4a9d4f8c6c523733ae59301bf53f4b153bc3`, `0xc971c780d6bdb91f81988faf81f662eaeb075b0bdfa9e7277bfedbd39da26bcd` | 16,378,940 / 16,378,953 | 1 |
| External swap 0.00215 MUSD → wrapper | `0xf996972556c8c11a49bf2a3857c38631dc69a313e584d97636bb424fa10e5cd1` | 16,378,984 | 1 |
| External exercise 1 lot | `0xf9376c6eafd76fbaeb96b1536814fad60c84e9f888b9aecae2af6c5e7fd4bab7` | 16,378,991 | 1 |

The external account received `1.002735998536819336` wrapper units, exercised `1e18`,
delivered `0.000001` ERC-20 BTC, and received `0.08` MUSD. The wrapper stayed 1:1 backed at
19 lots. Full approvals and funding are in [`COMPOSABILITY.md`](COMPOSABILITY.md).

---

## 5. Live state snapshot

Snapshot taken at **block 16,379,045**, **2026-10-26 10:15:56 UTC**. Values move
with interest, trading, and exercises.

### 5.1 Main series

| Field | Value |
| --- | --- |
| `active_lots` | `74` |
| `totalSupply()` | `74` |
| `collateral_balance_raw` | `1497.92e18` |
| `reserved_raw` | `5.92e18` |
| `excess_raw` | `1492e18` |
| `total_deposited_raw` | `1500e18` |
| `total_payouts_raw` | `2.08e18` |
| `expiry_release_raw` | `0` |
| `premium_balance_raw` | `0` |
| `expired` | `false` |
| `expiry` | `1795519026` — 2026-11-24 11:17:06 UTC |
| Position holders | buyer 25; deployer 5 direct + 5 through wrapper; pool 13.997264001463180664 through wrapper; external 0.002735998536819336 through wrapper; order-book escrow 25 |

### 5.2 Demo series

| Field | Value |
| --- | --- |
| `active_lots` | `0` |
| `totalSupply()` | `10` (frozen) |
| `collateral_balance_raw` | `0` |
| `expiry_release_raw` | `20e18` |
| `premium_balance_raw` | `0.01e18` |
| `expired` | `true` |
| `expiry` | `1792929664` — 2026-10-25 12:01:04 UTC |
| Writer | deployer EOA, not the vault |

### 5.3 Order book

| Field | Value |
| --- | --- |
| `nextListingId` | `2` |
| Listing `1` seller | `0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5` |
| Listing `1` series | main series |
| Listing `1` price | `0.002 MUSD` per lot |
| Listing `1` remaining | `25` lots |
| Listing `1` active | `true` |

The original 50-lot listing was partially filled: 25 lots bought by the deployer, 25
remain escrowed.

### 5.4 Vault

| Field | Value |
| --- | --- |
| MUSD balance | `400e18` |
| `idleMUSD()` | `400e18` |
| `reservedMUSD()` | `0` |
| ERC-20 BTC held | `0.000026 BTC` |
| `premiumForwarded()` | `0.1e18` |
| `expiryForwarded()` | `0` |
| `totalDepositedToSeries()` | `1,500e18` |
| Owner | `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3` |
| Bound series | main series |

### 5.5 Position wrapper

| Field | Value |
| --- | --- |
| Address | `0x4726a021ec380a755EBE883BEb800A5d06723E41` |
| Wrapped series | main series |
| `UNIT` | `1e18` |
| `totalSupply()` | `19e18` |
| `underlyingLots()` | `19` |
| Series token balance | `19` |
| `isLive()` | `true` |
| Deployer balance | `5e18` |
| Pool balance | `13.997264001463180664e18` |
| External balance | `0.002735998536819336e18` |

### 5.6 Wrapper/MUSD pool

| Field | Value |
| --- | --- |
| Address | `0xED305fEF4c11f95dAe1d144e78B2B62be50965F2` |
| Symbol | `vAMM-MUSD/wRBTC-PUT` |
| MUSD reserve | `0.03214914e18` |
| Wrapper reserve | `13.997264001463180664e18` |
| Implied marginal price | `0.002296816006088 MUSD` per lot |
| LP total supply | `670.820393249936907` |
| Deployer LP balance | `670.820393249935907` |
| External LP balance | `0` |
| `factory.isPool(pool)` | `true` |

### 5.7 Trove

| Field | Value |
| --- | --- |
| Native BTC collateral | `0.043 BTC` |
| Trove debt | `2,202.057203102504956752 MUSD` |
| ICR | `1.568564521549903788` — **156.856%** |
| Mezo BTC price | `80,327.18147 MUSD/BTC` |
| Trove status | `1` (active) |
| Application minimum ICR | `1.5e18` — 150% |
| Mezo liquidation MCR | 110% |
| MUSD gas compensation | `200 MUSD` |

### 5.8 Account balances

| Account | MUSD | ERC-20 BTC |
| --- | --- | --- |
| Deployer / vault owner | `50.01 MUSD` | `0.004697993136676592 BTC` |
| Buyer | `51.94 MUSD` | `0.0019749992572 BTC` |
| External pool buyer | `0.08785 MUSD` | `0.000300999867586176 BTC` |

The deployer MUSD balance includes the 20 MUSD demo expiry release. The external account
was funded by the deployer with `0.0003` native gas BTC, `0.01 MUSD`, and `0.000002`
ERC-20 BTC.
The ERC-20 BTC column is each account's liquid BTC balance through Mezo's ERC-20
interface. The trove's `0.043` native BTC is locked collateral and is not included.

---

## 6. Critical accounting finding

Mezo adds a borrowing fee to the trove debt. At the observed 0.1% rate:

```text
requested borrow:          2,000 MUSD
borrowing fee:                 2 MUSD
MUSD gas compensation:       200 MUSD
initial trove debt:        2,202 MUSD
current debt:              2,202.057203102504956752 MUSD
close repayment required = debt - 200 gas compensation
                          = 2,002.057203102504956752 MUSD
```

The vault holds `400 MUSD` idle. The owner holds `50.01 MUSD`. Available:

```text
400 + 50.01 = 450.01 MUSD
shortfall   = 2,002.057203102504956752 - 450.01
            = 1,552.047203102504956752 MUSD
```

The series holds `1,497.92 MUSD` of collateral, but that MUSD belongs to the series
reserve and is not available to repay the trove while the series is live. The wrapper is
not trove collateral. Calling `closeTrove()` now would revert for insufficient MUSD.

A live Mezo Pools MUSD/BTC pool exists at
`0xd16A5Df82120ED8D626a1a15232bFcE2366d6AA9` (approximately `102,535.53 MUSD` /
`1,303.716 BTC`, about `78,648.65 MUSD/BTC` at the snapshot). Selling all of the deployer's
free `0.004697993136676592` BTC would yield roughly `377.38 MUSD` before fees, still
leaving a gap above `1,170 MUSD` and no BTC for gas or settlement. The pool is a swap
route, not a close solution. Therefore:

- **trove closure is not demonstrated**;
- **do not claim the trove can be closed profitably or at all with current balances**;
- interest continues to accrue and changes the shortfall;
- a BTC price fall or debt rise reduces the ICR;
- liquidation would be a serious event for the vault owner, and the series reserve is
  accounted for separately but does not make the owner whole.

The contract tests include the close-repayment path, including preservation of reserved
expiry proceeds. The live close is blocked by liquidity, not by missing code.

---

## 7. Not performed

- Independent audit or formal verification.
- Main-series expiry and `finalize()`.
- Live trove `closeTrove()`.
- Live `repayMUSD`, `withdrawColl`, or liquidation/redemption flows against Mezo.
- Local fork execution of the Mezo BTC token.
- Load, griefing, or economic-security analysis.
- Organic demand or market-based premium discovery.
- MEZO governance-token integration.
- Organic wrapper/MUSD liquidity; the pool is deployer-seeded and thin.
- Pool-side exercise, or wrapper settlement after expiry.
- Wrapper/pool support in the web app.
- A wallet transaction sent through the web app.
- An automated end-to-end browser test suite or hosted app deployment.
- Mainnet deployment.

---

## 8. Claims that are safe

It is accurate to say:

- Roster is deployed on Mezo testnet, chain 31611.
- The contracts compiled, formatted, and passed 91/91 tests in default and CI profiles.
- A real Mezo trove was opened with native BTC and borrowed MUSD.
- A live series was funded, purchased, listed, filled, exercised, and had premium
  withdrawn.
- A separate demo series expired and released collateral.
- The order book is live with one open ask.
- A wrapper holds actual main-series lots 1:1, and a Mezo Pools pool holds the wrapper
  against MUSD.
- A separate generated account acquired wrapper tokens through the Mezo router and
  exercised one lot, delivering ERC-20 BTC and receiving the fixed MUSD payout.
- The five-page web app production build succeeds.
- The five pages loaded live RPC data in a read-only browser pass at desktop and mobile
  widths, with screenshots recorded; the pass predates the wrapper/pool.
- No audit, organic demand, trove closure, main expiry, organic wrapper liquidity, or
  wallet-tested app is claimed.

## 9. Claims that are not safe

Do not say:

- "audited", "production-ready", or "safe for real funds";
- "the trove was closed" or "profitable";
- "the main series expired" or "finalized";
- "there is demand" or "the premium is market-discovered";
- "the app is finished", "wallet-tested", "transaction-tested", or "fully validated";
  read-only screenshots exist, but no wallet transaction has been sent through the UI;
- "native BTC and ERC-20 BTC are interchangeable through Roster";
- "the wrapper/MUSD pool is deep, organic, or a Roster market";
- "the wrapper is collateral or redeemable for series collateral/native BTC";
- "the pool can exercise its own positions";
- "the app supports the wrapper or pool";
- "the project uses MEZO";
- "a fork test executed Mezo liquidation or close flows";
- "the series reserve makes the trove risk-free".
