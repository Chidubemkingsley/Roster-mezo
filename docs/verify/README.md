# Contract Verification Files

Flattened source and standard JSON input files for manual verification on the
Mezo testnet explorer (https://explorer.test.mezo.org).

## Compiler settings (all contracts)

| Setting | Value |
|---|---|
| Compiler | Solidity `0.8.24` |
| EVM version | `shanghai` |
| Optimizer | enabled, `200` runs |
| via IR | `true` |
| License | MIT |

## Addresses (Wave 2)

| Contract | Address |
|---|---|
| `RosterSeriesFactory` | `0x1ee9eCc9E526c41c9D190dDD06FF286deb6727c9` |
| `RosterOrderBook` | `0xeecAb683D93a483669D797E4B7a06e8c286A25dC` |
| `RosterTroveWriter` | `0xc3Ff91EF99fcB8AE19CAc7698BB1eFAAd704C243` |
| `RosterBtcPutSeries` | `0x68540003Ee52F73C3F2D8D6508227E8eCd5E767b` |

## Constructor arguments

### RosterSeriesFactory
```
musd_      = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
btc_       = 0x7b7C000000000000000000000000000000000000
feeRecip   = 0x90356CF97B3BF1749A604d3F89b3DF3602A459E3
feeBps     = 50
```
ABI-encoded:
```
0x000000000000000000000000118917a40faf1cd7a13db0ef56c86de7973ac503
0000000000000000000000007b7c000000000000000000000000000000000000
00000000000000000000000090356cf97b3bf1749a604d3f89b3df3602a459e3
0000000000000000000000000000000000000000000000000000000000000032
```

### RosterOrderBook
```
musd_         = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
factory_      = 0x1ee9eCc9E526c41c9D190dDD06FF286deb6727c9
feeRecipient_ = 0x90356CF97B3BF1749A604d3F89b3DF3602A459E3
fillFeeBps_   = 30
```
ABI-encoded:
```
0x000000000000000000000000118917a40faf1cd7a13db0ef56c86de7973ac503
0000000000000000000000001ee9ecc9e526c41c9d190ddd06ff286deb6727c9
00000000000000000000000090356cf97b3bf1749a604d3f89b3df3602a459e3
000000000000000000000000000000000000000000000000000000000000001e
```

### RosterTroveWriter
```
owner_                = 0x90356CF97B3BF1749A604d3F89b3DF3602A459E3
borrowerOperations_   = 0xCdF7028ceAB81fA0C6971208e83fa7872994beE5
troveManager_         = 0xE47c80e8c23f6B4A1aE41c34837a0599D5D16bb0
priceFeed_            = 0x86bCF0841622a5dAC14A313a15f96A95421b9366
musd_                 = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
btc_                  = 0x7b7C000000000000000000000000000000000000
minICR_               = 1500000000000000000 (1.5e18)
```

### RosterBtcPutSeries
```
writer_           = 0xc3Ff91EF99fcB8AE19CAc7698BB1eFAAd704C243
musd_             = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503
btc_              = 0x7b7C000000000000000000000000000000000000
K_raw_            = 80000000000000000000000
premium_per_lot_  = 1000000000000000
expiry_           = 1796150061
name_             = "Roster Wave 2 BTC Put"
symbol_           = "rBTC-PUT-W2"
feeRecipient_     = 0x90356CF97B3BF1749A604d3F89b3DF3602A459E3
feeBps_           = 50
```

## How to verify via the Mezo explorer UI

1. Open `https://explorer.test.mezo.org/address/<ADDRESS>/contract`
2. Click **"Verify and publish"**
3. Choose **"Solidity (Standard JSON input)"**
4. Upload the corresponding `*_standard_input.json` file from this directory
5. Enter the constructor arguments shown above
6. Submit — the explorer will recompile and match the deployed bytecode

Alternatively use **"Solidity (Flattened source code)"** with the `*_flat.sol` file
and manually enter each constructor argument.
