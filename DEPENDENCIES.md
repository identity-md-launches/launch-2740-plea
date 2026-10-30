# Vendored dependencies

All required Solidity sources are included as ordinary files. No git submodules,
package manager, or network access is needed to build or test once the pinned
compiler and Foundry are installed.

| Dependency | Version | Exact upstream commit | Included files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20 and its four transitive Solidity imports, MIT license |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Complete `src/` Solidity sources, Apache-2.0 and MIT licenses |

The upstream source and license files are unmodified. `remappings.txt` maps
imports to these local paths. OpenZeppelin is the only production dependency;
forge-std is used for tests.

`lib/SHA256SUMS` records each included file's SHA-256 checksum. Verify it from the
repository root with:

```sh
sha256sum -c lib/SHA256SUMS
```

Archives were fetched from GitHub's codeload endpoint using the exact commits
above. Archive SHA-256 values at retrieval were:

- OpenZeppelin: `4a9c091852052f4319173629e0bf0b5cdf7a39d70e5e2298a7a6a149eff9f385`
- forge-std: `a387f7c2a10387f889b0d18b999cfa667a5273ac11cc11e18923022eb8b24bc3`

The protocol interface follows [ERC-20](https://eips.ethereum.org/EIPS/eip-20).
The deployment adds only a named fixed supply and a constructor mint to
OpenZeppelin's ERC-20 implementation.
