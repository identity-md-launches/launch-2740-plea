# PLEA tests

The tests exercise the actual `src/PLEA.sol` deployment and the vendored ERC-20
implementation. They require no network, RPC, added dependencies, or storage
patching. Test actors are local fixtures, not launch recipients.

`PLEA.t.sol` retains the existing constructor, metadata, mint event, factory,
transfer, approval, failure, and token-level launch-flow checks. Arbitrary
nonzero recipients are generated with `bound`, without discarding fuzz cases.

`PLEA.edge.t.sol` adds ten unit tests and four properties at 1,000 runs each:

- One wei cannot be spent twice; the largest finite approval must decrease.
- A maximum-sized transfer must report insufficient balance without losing
  approval or changing supply.
- Owner, spender, and recipient aliases preserve balances and authorization.
- Infinite approvals can be reduced and revoked, and approvals are isolated by
  both owner and spender.
- Replacing a partially spent approval sets exactly the new value.
- Failed delegated transfers preserve arbitrary large approvals.
- Splitting an authorized transfer has the same result as spending it once.
- Repeated round trips preserve every token, including dust and full balances.

## Stateful properties

`PLEA.invariant.t.sol` uses four actors and eleven targeted handler actions.
Each actor starts funded; initial approvals include finite and infinite values.
Random transfers, approvals, revocations, invalid recipients/spenders, and
overdraw attempts are interleaved for 256 runs of 128 calls. Inputs include zero,
one wei, full balances/allowances, and both `uint256.max - 1` and `uint256.max`.

The balance and allowance models are updated from requested operations, never
copied from the token after a call. Failed actions require the precise custom
error and leave the model untouched. Preparatory approvals are recorded before
an attempted invalid transfer. The invariants then compare all four balances
and all sixteen owner/spender allowance pairs after every handler action.
Unexpected reverts fail the campaign.

The property review used the five discovery passes in the supplied Pashov fizz
reference, with the supplied Trail of Bits guide for generator and assertion
review. These are the applicable properties and their grounds:

| Review pass | Property and evidence | Check |
| --- | --- | --- |
| Conservation | The requested `10^27` units are minted once (`src/PLEA.sol:10–14`); transfers conserve the sum of balances (`ERC20.sol:188–215`). | Fixed supply, sum of actor balances, and individual balance model. |
| State transitions | Approval replacement and finite/infinite spending semantics (`ERC20.sol:284–319`). Reverting EVM calls roll back all updates. | Entire allowance matrix, revocation attempts, failure handlers, and replacement fuzz property. |
| Round trips | Transfers have no fees or rounding (`ERC20.sol:188–215`). Moving an amount back restores both balances. | Repeated-cycle and split-transfer fuzz properties, anchored to exact expected balances. |
| Adversarial inputs | An unapproved spender cannot debit a holder (`ERC20.sol:154–158, 310–319`); a valid holder can move its entire balance (`ERC20.sol:109–112, 171–178`). | Invalid/overdrawn actions, alias tests, full-balance handler, and final-state sweep. |
| Token semantics | PLEA metadata and constructor supply are fixed; zero recipients/spenders are rejected (`src/PLEA.sol:10–14`, `ERC20.sol:171–178, 284–295`). | Metadata invariant, zero balance/allowance assertions, boundary actions, and existing mint-event tests. |

`ERC20.sol` above is
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. These are intended
guarantees of this concrete fixed-supply implementation, not speculative vault,
pool, or governance properties. There are no conversions, shares, debts, or
withdrawal queues to model.

After each random sequence, `afterInvariant` consolidates every actor's full
balance into the first actor and rechecks both models. This checks that failures
and approval changes have not left any holder unable to move its funds.

The closed actor set makes the balance sum exhaustive for generated calls. It
does not model arbitrary contracts, live pool pricing, or transaction ordering
outside the generated sequence. The supplied protected launch tests refer to a
separate factory/pool/manifest harness absent from this repository; the local
launch-flow test checks exact token movements, not a live Uniswap swap.

## Reproduction

From the repository root:

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0xab9dfaf5c8338c20470b8a9bb528301a4467adcfbcb6114c74d3224e14981495 forge test --offline
```

To keep local build artifacts within the scratch directory, prefix either
command with `FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`.
No submitted test imports or depends on scratch contents.
