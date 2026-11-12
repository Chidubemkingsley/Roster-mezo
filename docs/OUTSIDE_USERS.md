# Outside User Evidence — Wave 2

Three independent wallet addresses participated in the Roster Wave 2
testnet demonstration. Each wallet performed a distinct on-chain action
through the app UI. None of these wallets is the deployer.

**Network:** Mezo testnet, chain ID `31611`
**Series:** `0x68540003Ee52F73C3F2D8D6508227E8eCd5E767b`
**Order book:** `0xeecAb683D93a483669D797E4B7a06e8c286A25dC`

---

## User 1 — Buy puts

| Field                | Value                                                                                                                                                                        |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wallet               | `0x7AC3E17d611a0D713A0001ede733682F96ab482c`                                                                                                                                 |
| Action               | `purchase(5)` on the series                                                                                                                                                  |
| Lots bought          | 5                                                                                                                                                                            |
| Premium paid         | 0.005 MUSD                                                                                                                                                                   |
| Protocol fee (0.5%)  | 0.000025 MUSD forwarded to feeRecipient                                                                                                                                      |
| Total charged        | 0.005025 MUSD                                                                                                                                                                |
| Transaction          | [`0x7878942da8e38aa3be5f71427b87c34179925b1085d945bc83b7143478aba084`](https://explorer.test.mezo.org/tx/0x7878942da8e38aa3be5f71427b87c34179925b1085d945bc83b7143478aba084) |
| Block                | 16,739,131                                                                                                                                                                   |
| Status               | 1 (success)                                                                                                                                                                  |
| Position tokens held | 5                                                                                                                                                                            |

On-chain event log confirms:

- `Transfer(0x0, 0x7AC3...482c, 5)` — 5 position tokens minted
- `Transfer(0x7AC3...482c, series, 0.005025 MUSD)` — buyer paid premium + fee
- `Transfer(series, feeRecipient, 0.000025 MUSD)` — protocol fee forwarded
- `ProtocolFeeCollected(feeRecipient, 0.000025 MUSD)` — fee event emitted
- `Purchased(0x7AC3...482c, 5, 0.005, 0.4)` — 5 lots, 0.005 premium, 0.4 MUSD reserve

---

## User 2 — Buy + list on secondary market

| Field                | Value                                                                                                                                                                        |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wallet               | `0xE205763A73194bF38E812727Ce5C8537d2F77429`                                                                                                                                 |
| Action               | Buy 3 lots, then list 3 lots on the order book                                                                                                                               |
| Lots bought          | 3                                                                                                                                                                            |
| Premium paid         | 0.003 MUSD                                                                                                                                                                   |
| Protocol fee (0.5%)  | 0.000015 MUSD forwarded to feeRecipient                                                                                                                                      |
| Total charged        | 0.003015 MUSD                                                                                                                                                                |
| Buy transaction      | [`0x8c0658310029adebb699859bc657db2139dded952ad51c9b1d9a3212c7f80bb9`](https://explorer.test.mezo.org/tx/0x8c0658310029adebb699859bc657db2139dded952ad51c9b1d9a3212c7f80bb9) |
| Buy block            | 16,739,299                                                                                                                                                                   |
| Listing price        | 0.002 MUSD/lot                                                                                                                                                               |
| Listing ID           | 2                                                                                                                                                                            |
| Listing transaction  | [`0xfc3ef54b2105b61f741c50cdaf8785d83281203c32c5adf9a8bb38c56a008d4e`](https://explorer.test.mezo.org/tx/0xfc3ef54b2105b61f741c50cdaf8785d83281203c32c5adf9a8bb38c56a008d4e) |
| Status               | ✅ Complete (buy + list both status 1)                                                                                                                                       |
| Position tokens held | 0 (all 3 escrowed in listing 2)                                                                                                                                              |

Buy transaction confirms:

- `Transfer(0x0, 0xE205...7429, 3)` — 3 position tokens minted
- `Purchased(0xE205...7429, 3, 0.003, 0.24)` — 3 lots, 0.003 premium, 0.24 MUSD reserve
- Protocol fee of 0.000015 MUSD forwarded to feeRecipient

Listing transaction confirms:

- `Approval(0xE205...7429, orderBook, 3)` — position tokens approved to book
- `Transfer(0xE205...7429, orderBook, 3)` — 3 lots escrowed
- `Listed(listingId=2, 0xE205...7429, series, 3, 0.002)` — public ask published

---

## User 3 — Fill the listing

| Field  | Value                                        |
| ------ | -------------------------------------------- |
| Wallet | `0xEBc4743135C585ca08BF649F424265EccfbA4d47` |
| Action | Fill User 2's listing on the order book      |
| Status | Pending                                      |

Instructions for User 3:

1. Connect MetaMask on Mezo testnet (chain 31611)
2. Go to the Secondary page
3. Find User 2's listing (3 lots at 0.002 MUSD/lot)
4. Click Fill — MetaMask will ask to approve MUSD to the order book, then confirm the fill

---

## Verification commands

```bash
RPC=https://rpc.test.mezo.org
SERIES=0x68540003Ee52F73C3F2D8D6508227E8eCd5E767b
BOOK=0xeecAb683D93a483669D797E4B7a06e8c286A25dC

# Check each user's position token balance
cast call $SERIES "balanceOf(address)(uint256)" 0x7AC3E17d611a0D713A0001ede733682F96ab482c --rpc-url $RPC
cast call $SERIES "balanceOf(address)(uint256)" 0xE205763A73194bF38E812727Ce5C8537d2F77429 --rpc-url $RPC
cast call $SERIES "balanceOf(address)(uint256)" 0xEBc4743135C585ca08BF649F424265EccfbA4d47 --rpc-url $RPC

# Check order book listings
cast call $BOOK "getListing(uint256)" 1 --rpc-url $RPC
cast call $BOOK "getListing(uint256)" 2 --rpc-url $RPC

# Check total fees collected
cast call $SERIES "total_fees_collected_raw()(uint256)" --rpc-url $RPC
```
