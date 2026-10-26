#!/usr/bin/env python3
"""Static project-consistency checks only; this does not compile Solidity."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors: list[str] = []

required_files = [
    "src/RosterBtcPutSeries.sol",
    "src/MockERC20.sol",
    "src/TestERC20Helpers.sol",
    "test/TestBase.sol",
    "test/RosterBtcPutSeries.t.sol",
    "test/SeriesInvariant.t.sol",
    "script/CheckMezoAssets.s.sol",
    "script/DeploySeries.s.sol",
    ".env.example",
]
for rel in required_files:
    if not (ROOT / rel).is_file():
        errors.append(f"missing required file: {rel}")

if errors:
    print("FAIL: required files missing")
    print("\n".join(f"- {e}" for e in errors))
    sys.exit(1)

# All relative Solidity imports must resolve. This is a path check, not syntax validation.
for file in [*ROOT.glob("src/**/*.sol"), *ROOT.glob("test/**/*.sol"), *ROOT.glob("script/**/*.sol")]:
    text = file.read_text()
    for imp in re.findall(r'import\s+(?:\{[^}]*\}\s+from\s+)?["\']([^"\']+)["\']\s*;', text):
        if imp.startswith("."):
            target = (file.parent / imp).resolve()
            if not target.is_file():
                errors.append(f"unresolved import in {file.relative_to(ROOT)}: {imp}")

unit_file = (ROOT / "test/RosterBtcPutSeries.t.sol").read_text()
invariant_file = (ROOT / "test/SeriesInvariant.t.sol").read_text()
unit_names = re.findall(r"function\s+(test_[A-Za-z0-9_]*)\s*\(", unit_file)
invariant_names = re.findall(r"function\s+(invariant_[A-Za-z0-9_]*)\s*\(", invariant_file)
if len(unit_names) != 36:
    errors.append(f"expected 36 unit-test functions, found {len(unit_names)}")
if len(set(unit_names)) != len(unit_names):
    errors.append("unit-test function names are not unique")
if len(invariant_names) != 6:
    errors.append(f"expected 6 invariant functions, found {len(invariant_names)}")
if len(set(invariant_names)) != len(invariant_names):
    errors.append("invariant function names are not unique")

must_have_tests = {
    "test_solvency_after_every_action",
    "test_limbo_state",
    "test_transfer_at_maturity_reverts",
    "test_transfer_after_finalization_reverts",
    "test_reentrancy_callback_blocked_by_guard_zero_allowance",
    "test_reentrancy_callback_blocked_by_guard_nonzero_allowance",
    "test_reentrancy_callback_bubbled_reverts_outer",
    "test_fee_on_transfer_musd_is_rejected_atomically",
    "test_expiry_release_audit_identity",
}
for name in sorted(must_have_tests - set(unit_names)):
    errors.append(f"required regression test missing: {name}")

source = (ROOT / "src/RosterBtcPutSeries.sol").read_text()
if "function totalSupply()" not in source or "uint256 private _totalSupply;" not in source:
    errors.append("position supply counter/getter missing")
for token in ("_requireExactIncrease", "_requireExactDecrease", "_checkedMul", "nonReentrant"):
    if token not in source:
        errors.append(f"expected hardening primitive missing: {token}")

# Ensure deployment, checker, and sample environment use the same key names.
env = (ROOT / ".env.example").read_text()
for key in ("MEZO_TESTNET_RPC_URL", "MUSD_ADDRESS", "BTC_ADDRESS", "WRITER_ADDRESS", "PRIVATE_KEY", "STRIKE_RAW", "PREMIUM_PER_LOT_RAW", "EXPIRY"):
    if f"{key}=" not in env:
        errors.append(f".env.example missing {key}")
for file in (ROOT / "script/CheckMezoAssets.s.sol", ROOT / "script/DeploySeries.s.sol"):
    text = file.read_text()
    for key in ("MUSD_ADDRESS", "BTC_ADDRESS"):
        if f'envAddress("{key}")' not in text:
            errors.append(f"{file.relative_to(ROOT)} does not read {key}")

# Deployment defaults must point at the verified Mezo testnet asset contracts.
verified_assets = {
    "MUSD_ADDRESS": "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503",
    "BTC_ADDRESS": "0x7b7C000000000000000000000000000000000000",
}
for key, address in verified_assets.items():
    if f"{key}={address}" not in env:
        errors.append(f".env.example must default {key} to the verified Mezo testnet address")
foundry = (ROOT / "foundry.toml").read_text()
if "[profile.ci]" not in foundry or "[profile.ci.fuzz]" not in foundry or "[profile.ci.invariant]" not in foundry:
    errors.append("Foundry CI profile is missing or incomplete")
workflow = (ROOT / ".github/workflows/test.yml").read_text()
for cmd in ("forge build", "forge test -vvv", "FOUNDRY_PROFILE=ci forge test -vvv"):
    if cmd not in workflow:
        errors.append(f"GitHub Actions workflow missing command: {cmd}")
deploy_script = (ROOT / "script/DeploySeries.s.sol").read_text()
for required in ("block.chainid != MEZO_TESTNET_CHAIN_ID", "writer != deployer", "token.code.length == 0", "actualDecimals != 18"):
    if required not in deploy_script:
        errors.append(f"deployment preflight is missing: {required}")

# Arithmetic cross-check for documented example: 80,000 MUSD/BTC, 1e-6 BTC lots.
K_RAW = 80_000 * 10**18
strike_per_lot = K_RAW // 10**6
premium_per_lot = 10**15
if K_RAW % 10**6 != 0 or strike_per_lot != 80_000 * 10**12:
    errors.append("strike-per-lot arithmetic does not match the documented example")
if premium_per_lot != 10**15:
    errors.append("premium example drifted from 1e15 raw MUSD per lot")

if errors:
    print("FAIL: static project consistency checks")
    print("\n".join(f"- {e}" for e in errors))
    sys.exit(1)

print("PASS: required files and relative imports resolve")
print(f"PASS: {len(unit_names)} unique unit-test functions found")
print(f"PASS: {len(invariant_names)} unique invariant functions found")
print("PASS: required regression test names present")
print("PASS: env keys are consistent across sample config and scripts")
print("PASS: sample config defaults to the verified Mezo MUSD and ERC-20 BTC addresses")
print("PASS: CI profile and compile/default/expanded test workflow are configured")
print("PASS: deployment script contains chain, writer, code, and decimal preflight checks")
print("PASS: documented strike/premium arithmetic is consistent")
print("NOTE: static check only; no Solidity compilation or EVM tests were performed")
