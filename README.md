# Points Hook — UHI "Build your first hook" homework

A Uniswap v4 hook, built for the Uniswap Hook Incubator (UHI) cohort exercise
_Build your first hook_. It mints an ERC-1155 "points" balance to a user each
time they buy `TOKEN` with ETH on a pool this hook is attached to, and — as
the small feature added on top of the canonical lesson example — pays a
smaller referral bonus to a second address the buyer opts in to name.

## What it does

- Hook permission: `afterSwap` only. All other flags off.
- On pools where `currency0 == 0x0` (native ETH) and the swap direction is
  ETH → TOKEN, the hook reads `hookData` and mints points equal to a fixed
  fraction of the ETH the swapper spent:
  - **User bonus**: 20% of ETH spent, minted to `user`.
  - **Referrer bonus**: 5% of ETH spent, minted to `referrer` — but only if
    `referrer != address(0)` and `referrer != user` (self-referring
    collapses cleanly to the plain-user case).
- Points are held as an ERC-1155 token whose `id` is the pool's `PoolId`
  reinterpreted as `uint256`, so each pool has its own points token.

### `hookData` encoding

The buyer chooses one of three shapes:

| bytes                                        | effect                                     |
|----------------------------------------------|--------------------------------------------|
| `""` (empty)                                 | no points minted                           |
| `abi.encode(address user)`                   | 20% to `user`                              |
| `abi.encode(address user, address referrer)` | 20% to `user`, 5% to `referrer` (if valid) |

Non-ETH pools and the reverse direction (TOKEN → ETH) are no-ops.

## Layout

```
src/PointsHook.sol           # the hook
test/PointsHook.t.sol        # 5 tests, all against the real v4 PoolManager
foundry.toml                 # solc 0.8.26, evm cancun
remappings.txt               # v4-hooks-public + v4-core + solmate
```

## Build & test

```bash
forge install
forge test -vv
```

Result: `5 passed; 0 failed`.

The tests cover:

1. User receives 20% of ETH spent as points on an ETH → TOKEN swap.
2. Referrer receives 5% when a distinct valid referrer is named.
3. No referrer bonus is minted when the referrer is `address(0)`.
4. No referrer bonus is minted when the buyer self-refers (`user == referrer`).
5. Empty `hookData` mints nothing.

Each test performs a real swap against a freshly-deployed `PoolManager` using
`PoolSwapTest`, with the hook address mined for the `AFTER_SWAP_FLAG` bit via
`HookMiner.find` and deployed by `CREATE2` at the mined address.

## Deploy (Sepolia)

`script/DeployPointsHook.s.sol` mines a valid hook address for `AFTER_SWAP_FLAG`
(bit 6) and deploys via CREATE2 against the canonical Uniswap v4 PoolManager on
Sepolia (`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`).

Copy `.env.example` to `.env` and fill in your `PRIVATE_KEY` (a Sepolia wallet
funded from any public faucet).

Dry-run (simulate, no broadcast):

```bash
forge script script/DeployPointsHook.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --chain-id 11155111
```

Broadcast:

```bash
forge script script/DeployPointsHook.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --chain-id 11155111 \
    --broadcast
```

RPC endpoints in `.env.example` are all free public Sepolia providers — no
Alchemy or Infura key required.

## Attribution

Built for the UHI "Build your first hook" quest by
[voltgzer0](https://github.com/voltgzer0). The canonical Points Hook lesson
material is by Atrium Academy / the UHI cohort staff; the referrer-bonus
feature and the tests around it are the piece added on top per the quest brief.

## Licence

MIT. See [LICENSE](./LICENSE).
