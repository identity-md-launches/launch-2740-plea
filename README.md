# PLEA

PLEA is a fixed supply ERC-20. Its constructor mints all **1,000,000,000 PLEA**
to the immediate deployer once. The contract uses the vendored OpenZeppelin
Contracts v5.0.2 ERC-20 implementation.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Source / Solidity identifier | `src/PLEA.sol:PLEA` |
| Name | `PLEA` |
| Symbol | `PLEA` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment transaction value | `0` ETH |
| Initial recipient | Constructor `msg.sender` |
| Target chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimization | Enabled, 200 runs |
| Bytecode metadata hash | None |

Deploy the compiled `PLEA` creation bytecode directly. Do not deploy it behind a
proxy. The constructor makes no external calls and requires no configuration,
linked libraries, external contracts, or initialization call. The build artifact
is `out/PLEA.sol/PLEA.json`.

When a factory deploys PLEA with CREATE or CREATE2, the **factory** receives the
entire supply. The transaction sender does not receive it automatically. The
launch factory is responsible for distributing that supply. There is no owner
or administrator of the token.

## Behavior and assumptions

- PLEA uses ordinary ERC-20 transfers and allowances. Successful `transfer`,
  `approve`, and `transferFrom` calls return `true`; invalid calls revert with
  OpenZeppelin's ERC-6093 custom errors.
- Transfers deliver the exact requested amount. There are no taxes, transfer
  fees, rebases, limits, exemptions, or recipient callbacks.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`.
  Self-transfers preserve the balance but still require sufficient funds.
- A recipient or approval spender cannot be the zero address. Transfers to zero
  do not provide a burn mechanism.
- `approve` replaces the caller's allowance for the spender. `transferFrom`
  consumes finite allowances; an allowance of `type(uint256).max` remains
  unchanged when spent. A holder using `transferFrom` on its own balance also
  needs an allowance; it can use `transfer` without one.
- Construction emits one `Transfer` from the zero address. Each transfer emits
  `Transfer`, and each explicit approval emits `Approval`. In this vendored
  implementation, spending an allowance does not emit another `Approval`;
  indexers should query `allowance` for the current value.
- Supply never changes after construction. There is no public mint, burn,
  pause, blacklist, seizure, ownership, upgrade, permit, or recovery function.
- The token has no payable entry point. ETH and other assets forcibly or
  accidentally sent to its address cannot be recovered through this contract.

The requested behavior is interpreted as a plain ERC-20 with fixed supply;
no extra token economics or application contracts are added.

## Launch integration

For the supplied launch economics, the factory routes 10% of the supply
(100,000,000 PLEA) to the launch distributor, 80% (800,000,000 PLEA) to pool
seeding, and the remaining 10% (100,000,000 PLEA) to
`0x863e974406764c8526b102c28a1e53906e032954`.
These transfers occur after deployment and are the factory's responsibility;
the constructor reserves or distributes none of them.

The launch pairs with native ETH, with the supplied 22 ETH opening market cap,
pool fee `12500` (1.25%), and tick spacing `60`. The launch system computes the
opening price and writes the manifest separately. These settings are not token
constructor arguments or token storage. This repository contains no launch
manifest or transaction broadcast script.

## Build and test

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xab9dfaf5c8338c20470b8a9bb528301a4467adcfbcb6114c74d3224e14981495 forge test
forge fmt --check
```

Dependencies are ordinary source files under `lib/`, with their licenses and
checksums. No dependency download, submodule initialization, RPC endpoint, wallet,
environment file, FFI, or filesystem cheatcode permission is needed. The Solidity
compiler is supplied by the execution environment, not vendored as a binary.
See [DEPENDENCIES.md](DEPENDENCIES.md) for pinned revisions.

`test/PLEA.t.sol` covers metadata, exact supply and mint event, CREATE2 factory
deployment, direct and delegated transfers, approvals and revocation, finite and
unlimited allowances, zero values, self-transfers, invalid addresses, insufficient
balances and allowances, atomic rollback, absent administrative powers, and exact
launch distribution and pool-facing token transfers. Five fuzz tests run 512
cases each by default.

`test/PLEA.invariant.t.sol` exercises randomized transfers, approvals, and delegated
transfers across four holders. Two invariants compare all balances and allowances
against an independent accounting model and enforce supply conservation across
128 sequences of 64 calls. Unexpected handler reverts fail the suite. Tests use
isolated deployments and do not read or change environment variables.

The local pool-facing test checks token movements, not a live Uniswap pool or
swap pricing. The supplied protected launch checks depend on the network's
separate factory, liquidity, pool, and manifest harness; that integration is
verified by the launch system.

## After launch

There are no owner settings, maintenance calls, or upgrade responsibilities.
The launch operator should verify the deployed source and compiler settings,
metadata, `10^27` total supply, constructor mint recipient, and subsequent factory
distribution against the accepted manifest.

Holders manage their transfers and spender approvals. Use limited approvals for
trusted spenders, revoke unused allowances, and when replacing an existing
allowance consider setting it to zero and waiting for confirmation first; the
standard ERC-20 approval ordering race remains. Tokens sent to an inaccessible
address, including the token contract itself, have no administrative recovery.

The implementation review and its limits are recorded in [SECURITY.md](SECURITY.md).
