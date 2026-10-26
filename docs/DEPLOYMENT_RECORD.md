# Deployment Record — Mezo Testnet

**Network:** Mezo testnet
**Chain ID:** `31611`
**RPC:** `https://rpc.test.mezo.org`
**Explorer:** `https://explorer.test.mezo.org`
**Snapshot:** block `16,359,943`, 2026-10-25 12:11:06 UTC
**Status:** live testnet demonstration; not audited; main series active; trove open

This record replaces the earlier placeholder deployment checklist. Every address,
transaction, and state value below was read from or broadcast to Mezo testnet. Values
that change with interest, trading, or time are marked as snapshot values.

Canonical project record: [`../README.md`](../README.md).
Validation status: [`VALIDATION_STATUS.md`](VALIDATION_STATUS.md).
Machine-readable copy: [`deployment.json`](deployment.json).

---

## 1. Accounts and key handling

| Role | Address | Key location |
| --- | --- | --- |
| Deployer / vault owner / demo writer | `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3` | outside the repository |
| Generated demo buyer | `0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5` | outside the repository |

The deployer key and buyer key were kept in mode-600 files outside the repository.
No private key, mnemonic, keystore, or `.env` file is committed. The repository only
contains the public `.env.example` template.

The demo buyer is a generated account, not an independent customer. Its trades
demonstrate that a non-writer account can purchase, list, fill, and exercise; they do
not demonstrate organic demand.

---

## 2. Deployed contracts

| Role | Contract | Address | Deployment transaction | Block | Status |
| --- | --- | --- | --- | --- | --- |
| Factory | `RosterSeriesFactory` | `0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F` | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` | 16,359,308 | 1 |
| Order book | `RosterOrderBook` | `0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25` | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` | 16,359,315 | 1 |
| Trove vault | `RosterTroveWriter` | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` | 16,359,322 | 1 |
| Main series | `RosterBtcPutSeries` | `0xC23167867baAF830D586598DE0634E26fD895b92` | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` | 16,359,328 | 1 |
| Demo series | `RosterBtcPutSeries` | `0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43` | `0xa7ff146b3ce49b46a8de4582c3826b320797b28d1e70fff7669530b4a10cabae` | 16,359,511 | 1 |

All five addresses have non-empty bytecode at the snapshot.

Explorer links:

- [Factory](https://explorer.test.mezo.org/address/0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F)
- [Order book](https://explorer.test.mezo.org/address/0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25)
- [Trove vault](https://explorer.test.mezo.org/address/0x214e2316EAEeE24c1dc5d8433329fFC7544DA331)
- [Main series](https://explorer.test.mezo.org/address/0xC23167867baAF830D586598DE0634E26fD895b92)
- [Demo series](https://explorer.test.mezo.org/address/0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43)

---

## 3. Assets and Mezo protocol contracts

| Role | Address | Notes |
| --- | --- | --- |
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` | 18 decimals; premium, collateral, debt |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` | 18 decimals; exercise asset; separate from native BTC |
| PriceFeed | `0x86bCF0841622a5dAC14A313a15f96A95421b9366` | `fetchPrice()` returns MUSD/BTC |
| BorrowerOperations | `0xCdF7028ceAB81fA0C6971208e83fa7872994beE5` | trove open/borrow/repay/close |
| TroveManager | `0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0` | debt, collateral, ICR, status |
| ActivePool | `0x143A063F62340DA3A8bEA1C5642d18C6D0F7FF51` | native BTC collateral pool |
| CollSurplusPool | `0xB4C35747c26E4aB5F1a7CdC7E875B5946eFa6fa9` | collateral surplus recovery |

The vault's constructor resolves `activePool` and `collSurplusPool` from
`BorrowerOperations`; the values above match the live deployment.

### 3.1 Native BTC vs ERC-20 BTC

Do not conflate these assets:

- **native BTC** is posted to Mezo as trove collateral through `msg.value`;
- **ERC-20 BTC** at `0x7b7C…0000` is delivered by an exercising holder.

Roster does not convert one into the other and makes no convertibility promise.

---

## 4. Main series terms

| Parameter | Value |
| --- | --- |
| Contract | `0xC23167867baAF830D586598DE0634E26fD895b92` |
| Name | `Roster Mezo BTC Put (Trove)` |
| Symbol | `rBTC-PUT-T` |
| Writer | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` (vault) |
| MUSD | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` |
| ERC-20 BTC | `0x7b7C000000000000000000000000000000000000` |
| `K_raw` | `80000000000000000000000` (80,000 MUSD/BTC) |
| `strike_per_lot_raw` | `80000000000000000` (0.08 MUSD) |
| `premium_per_lot_raw` | `1000000000000000` (0.001 MUSD) |
| `LOT_SIZE_RAW` | `1000000000000` (0.000001 BTC) |
| Expiry | `1795519026` — 2026-11-24 11:17:06 UTC |
| Initial writer deposit | 1,500 MUSD |
| Position decimals | `0` |

### 4.1 Capacity

```text
one lot                  = 0.000001 BTC
strike per lot           = 80,000 / 1,000,000 = 0.08 MUSD
initial deposit          = 1,500 MUSD
maximum lots             = 1,500 / 0.08 = 18,750
maximum BTC notional     = 1,500 / 80,000 = 0.01875 BTC
```

After 25 lots were exercised:

```text
collateral               = 1,498 MUSD
reserved                 = 6 MUSD  (75 active lots x 0.08)
excess                   = 1,492 MUSD
remaining capacity       = 18,650 lots
```

The capacity is intentionally small. It is a testnet demonstration, not a deep market.

---

## 5. Trove terms and state

| Parameter | Value |
| --- | --- |
| Vault | `0x214e2316EAEeE24c1dc5d8433329fFC7544DA331` |
| Owner | `0x90356CF97B3BF1749A604d3F89b3DF3602A459E3` |
| Bound series | main series |
| Native BTC collateral | `0.043 BTC` |
| Initial requested borrow | 2,000 MUSD |
| Borrowing fee at open | 2 MUSD (0.1%) |
| MUSD gas compensation | 200 MUSD |
| Initial debt | 2,202 MUSD |
| Current debt | `2,202.001777260997830208 MUSD` |
| Current ICR | `1.569883623935996387` — 156.99% |
| Mezo BTC price | `80,392.71 MUSD/BTC` |
| Trove status | `1` (active) |
| Application minimum ICR | `1.5e18` — 150% |
| Mezo liquidation MCR | 110% |

The debt grows with interest. The ICR is a snapshot and moves with BTC price and debt.

### 5.1 Trove funding

The vault:

1. opened a real Mezo trove with 0.043 native BTC;
2. borrowed 2,000 MUSD;
3. incurred a 2 MUSD borrowing fee, which was added to the debt;
4. carried 200 MUSD of gas compensation in the debt;
5. deposited 1,500 MUSD into the main series;
6. retained 500 MUSD, then withdrew 100 MUSD idle to the owner, leaving 400 MUSD idle.

Live transaction:
`0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3`

---

## 6. Transaction ledger

All listed transactions have receipt status `1`.

### 6.1 Deployment and binding

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Deploy factory | `0x7820fd49212c721e3671a63f9a28e9c47b6056dbf15cd0dec9d0ec2beeab2c76` | 16,359,308 | 2,500,000 |
| Deploy order book | `0xe99ced935a65633f7ecfeb6f789dd0cba5b278da59b81192d6d40783675f906f` | 16,359,315 | 2,500,000 |
| Deploy trove vault | `0x6266c2c646f0d2cbabe48fba10afa528787f9f159814aea2567170176739b027` | 16,359,322 | 2,500,000 |
| Create main series | `0xf93e75fbcf23a7805ad8d7bb7ff657d8b3fcdbb2133b4e47cea40cec5abe409b` | 16,359,328 | 5,000,000 |
| Bind vault to series | `0x475ac4a22814c979e736d56644e74e51c26028c0a76edc24a7a6596461162929` | 16,359,339 | 1,000,000 |
| Open trove and fund series | `0xf77a65faa269621d3b0c7c5f0f3bf2aba02da742c0f7448e9bfb89cef6d74cb3` | 16,359,352 | 5,000,000 |

### 6.2 Main-series lifecycle

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Withdraw 100 MUSD idle from vault | `0x42382fc32c88c42c7f16d8039f8bd7ea677d9575492ea1dc26d9b98fa3e122b1` | 16,359,394 | 1,000,000 |
| Fund buyer with 50 MUSD | `0xfcdedbe4097ef8c5b874ec18535cca1fae9846b5c75419a3a84d0fbbf82c3e8c` | 16,359,397 | 100,000 |
| Fund buyer with 0.001 ERC-20 BTC | `0x7955e79d23d2490e008a4ef92dcf95cdc4db63b8780bc987c3dd62f470f9e54a` | 16,359,411 | 100,000 |
| Buyer approves MUSD to series | `0x21a70bfcc088cfbae46bba0e1856b28527f7a8e044fb8c78223562e27f229a63` | 16,359,416 | 100,000 |
| Buyer purchases 100 lots (0.1 MUSD premium) | `0xe267876b92c517fd0f12f52b8f3935f683bdca6eda8b832c1837bc11e14c7186` | 16,359,419 | 1,000,000 |
| Buyer approves position tokens to book | `0x49fd70c707bfc9590cb0afb4d4665b4677b3f2ee5b99b7bad1f1889f5d20a169` | 16,359,426 | 100,000 |
| Buyer lists 50 lots at 0.002 MUSD/lot | `0x4c28017a4ca2f99c261b54ad30ecd4e21382b1e931eaae092fa76eda7ff3752e` | 16,359,433 | 500,000 |
| Deployer fills 25 lots (0.05 MUSD) | `0xd02d308ffd79ae818b78d88563189ffd9a3f88b72a13b0f93a73a4e1e5a2894e` | 16,359,445 | 500,000 |
| Buyer exercises 25 lots (0.000025 BTC → 2 MUSD) | `0x4230a5c81c8e351634306885098e5ad3765b27564c3d6ff08462815ce36f4991` | 16,359,457 | 500,000 |
| Vault withdraws 0.1 MUSD premium | `0x5f82341945dba350e179211cabb5031228844eebfb328acb9112bee715ce8a50` | 16,359,469 | 250,000 |

### 6.3 Demo series lifecycle

The demo uses the deployer EOA as writer, not the trove vault.

| Step | Transaction | Block | Gas |
| --- | --- | --- | --- |
| Create demo series | `0xa7ff146b3ce49b46a8de4582c3826b320797b28d1e70fff7669530b4a10cabae` | 16,359,511 | 2,500,000 |
| Approve 20 MUSD to demo series | `0x4280f849273e419d07533f3d205047f264422805b0f511e7289e883eb464f0c4` | 16,359,517 | 100,000 |
| Deposit 20 MUSD | `0x89c016b7f19d87e89dba2ae8c3ecc4a5081b15a87d5ea681a5e328bea4275946` | 16,359,519 | 500,000 |
| Buyer approves 0.01 MUSD | `0x5f52c73be0789064f6894bbbcea0d18df19113c77e665ba84141880a62487aa9` | 16,359,524 | 100,000 |
| Buyer purchases 10 lots | `0xafa7a0e6227dd3d2d5eca8cd16e072a9443331a8d5f86cdc4480b568c6ba3815` | 16,359,527 | 500,000 |
| `expire()` after maturity | `0xdc1b099d2f1a6256de62fdb28698167728416a9fb9df895ac19062d81eb5dd8d` | 16,359,832 | 91,904 |

Demo expiry result:

```text
expired              = true
expiry_release_raw   = 20 MUSD
collateral_balance   = 0
active_lots          = 0
reserved_raw         = 0
excess_raw           = 0
totalSupply()        = 10 (frozen)
premium_balance_raw  = 0.01 MUSD (still withdrawable)
```

---

## 7. Current state snapshot

Snapshot at **block 16,359,943**, **2026-10-25 12:11:06 UTC**.

### 7.1 Factory

| Field | Value |
| --- | --- |
| `seriesCount()` | `2` |
| Series 0 | main series `0xC231…5b92` |
| Series 1 | demo series `0xCC6b…FA43` |

### 7.2 Main series

| Field | Value |
| --- | --- |
| `active_lots` | `75` |
| `totalSupply()` | `75` |
| `collateral_balance_raw` | `1,498 MUSD` |
| `reserved_raw` | `6 MUSD` |
| `excess_raw` | `1,492 MUSD` |
| `total_deposited_raw` | `1,500 MUSD` |
| `total_payouts_raw` | `2 MUSD` |
| `expiry_release_raw` | `0` |
| `premium_balance_raw` | `0` |
| `expired` | `false` |

Position distribution:

| Holder | Lots |
| --- | --- |
| Buyer `0x1A1A…Dd3b5` | 25 |
| Deployer `0x9035…9E3` | 25 |
| Order book escrow | 25 |
| **Total** | **75** |

### 7.3 Demo series

| Field | Value |
| --- | --- |
| `active_lots` | `0` |
| `totalSupply()` | `10` |
| `collateral_balance_raw` | `0` |
| `expiry_release_raw` | `20 MUSD` |
| `premium_balance_raw` | `0.01 MUSD` |
| `expired` | `true` |

### 7.4 Order book

| Field | Value |
| --- | --- |
| `nextListingId` | `2` |
| Open listings | `1` |
| Listing 1 seller | `0x1A1A70AF037123dda8A1B49BA245234f318Dd3b5` |
| Listing 1 series | main series |
| Listing 1 price | `0.002 MUSD` per lot |
| Listing 1 remaining | `25` lots |
| Listing 1 active | `true` |

### 7.5 Vault

| Field | Value |
| --- | --- |
| MUSD balance | `400 MUSD` |
| `idleMUSD()` | `400 MUSD` |
| `reservedMUSD()` | `0` |
| ERC-20 BTC balance | `0.000025 BTC` |
| `premiumForwarded()` | `0.1 MUSD` |
| `expiryForwarded()` | `0` |
| `totalDepositedToSeries()` | `1,500 MUSD` |

### 7.6 Trove

| Field | Value |
| --- | --- |
| Native BTC collateral | `0.043 BTC` |
| Debt | `2,202.001777260997830208 MUSD` |
| ICR | `1.569883623935996387` — 156.99% |
| Price | `80,392.71 MUSD/BTC` |
| Status | `1` (active) |

### 7.7 Account balances

| Account | MUSD | ERC-20 BTC |
| --- | --- | --- |
| Deployer / vault owner | `50.05 MUSD` | `0.004999993948523024 BTC` |
| Buyer | `51.94 MUSD` | `0.0019749992572 BTC` |

Native BTC is separate and not included in the ERC-20 BTC column.

---

## 8. Trove close status

At the snapshot:

```text
current debt                    2,202.001777260997830208 MUSD
gas compensation                  200.000000000000000000 MUSD
close repayment required        2,002.001777260997830208 MUSD
vault idle MUSD                   400.000000000000000000 MUSD
owner MUSD                         50.050000000000000000 MUSD
available                         450.050000000000000000 MUSD
shortfall                       1,551.951777260997830208 MUSD
```

The series reserve of 1,498 MUSD is held by the main series and is not available to
repay the trove while the series is live. `closeTrove()` is therefore **not
demonstrated**. The contract path is tested, but the live account cannot fund it.

No live Mezo testnet DEX route for the missing MUSD was found. The documented pool
`0x52e604c44417233b6CcEDDDc0d640A405Caacefb` had no code at the time of checking.

Do not claim:

- that the trove was closed;
- that it is profitable;
- that the series reserve is free collateral;
- that closing is possible without additional MUSD.

---

## 9. Live verification commands

```bash
RPC=https://rpc.test.mezo.org

cast chain-id --rpc-url "$RPC"

# Factory
cast call 0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F \
  "seriesCount()(uint256)" --rpc-url "$RPC"
cast call 0xEeCCD2bb5c0605F3eaCDC4dA221D9bdeDa580D2F \
  "allSeries()(address[])" --rpc-url "$RPC"

# Main series
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "active_lots()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "collateral_balance_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "reserved_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "excess_raw()(uint256)" --rpc-url "$RPC"
cast call 0xC23167867baAF830D586598DE0634E26fD895b92 \
  "expired()(bool)" --rpc-url "$RPC"

# Demo series
cast call 0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43 \
  "expired()(bool)" --rpc-url "$RPC"
cast call 0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43 \
  "expiry_release_raw()(uint256)" --rpc-url "$RPC"
cast call 0xCC6bEA372b4947D31303FAb5d13C2f984d68FA43 \
  "totalSupply()(uint256)" --rpc-url "$RPC"

# Vault and trove
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "idleMUSD()(uint256)" --rpc-url "$RPC"
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "reservedMUSD()(uint256)" --rpc-url "$RPC"
cast call 0x214e2316EAEeE24c1dc5d8433329fFC7544DA331 \
  "troveInfo()(uint256,uint256,uint256,uint256,uint8)" --rpc-url "$RPC"

# Order book
cast call 0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25 \
  "nextListingId()(uint256)" --rpc-url "$RPC"
cast call 0xc97B2fe5ba7e68ed7b52a657a137Cf636149cd25 \
  "getListing(uint256)((address,address,uint256,uint256,bool))" 1 --rpc-url "$RPC"

# Receipt checks
cast receipt 0xdc1b099d2f1a6256de62fdb28698167728416a9fb9df895ac19062d81eb5dd8d \
  --rpc-url "$RPC"
```

---

## 10. Deployment method

The intended one-shot deployment script is
[`../script/DeployStack.s.sol`](../script/DeployStack.s.sol). It cannot be simulated
locally against Mezo's BTC token because its `decimals()` call reverts under local
Foundry/revm forks (`EvmError: NotActivated`). Live `cast` calls and transactions
succeed.

The live stack was therefore deployed in stages:

1. Deploy `RosterSeriesFactory(musd, btc)`.
2. Deploy `RosterOrderBook(musd, factory)`.
3. Deploy `RosterTroveWriter(owner, borrowerOps, troveManager, priceFeed, musd, btc,
   minICR)`.
4. Call `factory.createSeries(vault, strike, premium, expiry, name, symbol)`.
5. Call `vault.bindSeries(series)`.
6. Call `vault.openAndFund{value: collateral}(requestedBorrow, seriesDeposit, hint,
   hint)`.
7. Verify state with `cast call`.

Operational note: Mezo's RPC intermittently returned a null response after a
transaction had already succeeded. `cast send --async` followed by receipt polling was
the reliable broadcast pattern.

---

## 11. Reproducibility checklist

Before treating a future deployment as valid:

- [ ] chain ID is `31611`;
- [ ] MUSD code exists and `decimals() == 18`;
- [ ] ERC-20 BTC code exists and `decimals() == 18`;
- [ ] BorrowerOperations, TroveManager, PriceFeed code exists;
- [ ] `MUSD_GAS_COMPENSATION()` matches the expected value;
- [ ] `getBorrowingFee()` is read at execution time;
- [ ] strike is divisible by `1_000_000`;
- [ ] expiry is an absolute future timestamp;
- [ ] `series.writer()` is the vault;
- [ ] `vault.series()` is the series;
- [ ] `vault.seriesBound() == true`;
- [ ] post-open ICR is at or above `minICR`;
- [ ] series collateral equals `reserved + excess`;
- [ ] position supply equals active lots before expiry;
- [ ] order book recognizes the factory series;
- [ ] no private key or `.env` is staged.

---

## 12. Known gaps and non-claims

- No audit.
- No organic demand.
- No market-based premium discovery.
- No trove closure.
- No main-series expiry or finalization.
- No MEZO governance-token integration.
- No liquidation/redemption bot.
- No DEX route for the close shortfall.
- No wallet transaction through the app; the five-page read-only browser pass and
  screenshots are recorded, but no wallet was connected.
- No automated app E2E suite or hosted app.
- No mainnet deployment.
- No guarantee that native BTC and ERC-20 BTC are convertible.
- No guarantee that the order book has a buyer.
- No guarantee that the trove remains above its minimum ICR.

The strongest accurate description is:

> A working Mezo testnet mechanism with real MUSD, a real trove, a live secondary book,
> verified lifecycle transactions, and a five-page app with read-only desktop/mobile
> browser evidence — but no audit, no organic demand, no premium discovery, no trove
> closure, no main expiry, and no wallet transaction through the UI.
