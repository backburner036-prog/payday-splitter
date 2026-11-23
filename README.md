# Payday Splitter — Reactive Omni Buildathon

> **Set It and Forget It track.** Payday comes in, your money splits itself —
> no bot, no keeper, no app to open. A Reactive contract on Reactive Lasna
> watches for your payday on Unichain Sepolia and splits every deposit into
> **savings / bills / fun**, automatically, in seconds.

Built for the [Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon/detail)
(Nov 5 – **Dec 5, 2026, 20:00 UTC** / Dec 6, 03:00 WIB), $5,500 in REACT.

## The loop (60 seconds, zero infrastructure)

```
You (Unichain Sepolia)          Reactive Lasna (5318007)        PaydaySplitter (Unichain)
─────────────────────           ────────────────────────        ─────────────────────────
setPlan(savings, bills,
  fun, 50/30/20)
payday() 0.05 ETH ──►
  PaydayReceived event ─────►  PaydayReactive.react()
                               requests callback ─────►  splitPayday()
                                                         0.025 → savings
                                                         0.015 → bills
                                                         0.010 → fun
```

1. **Set a plan once** — three beneficiary addresses + shares (basis points,
   must sum to 10,000).
2. **On payday, deposit** — `payday()` escrows the ETH and emits
   `PaydayReceived(user, amount, timestamp)`.
3. **Reactive does the rest** — `PaydayReactive` (Lasna) is subscribed to
   that event; on `react()` it requests a cross-chain callback.
4. **The split lands on-chain** — the Reactive callback proxy calls
   `splitPayday()`, which pays the three beneficiaries. Dust below 0.001 ETH
   is ignored (on both sides), and integer-division remainder goes to fun.

## Contracts

| Contract | Chain | Address |
|---|---|---|
| `PaydaySplitter` | Unichain Sepolia (1301) | _TBD after deploy — see `deployments.json`_ |
| `PaydayReactive` | Reactive Lasna (5318007) | _TBD after deploy — see `deployments.json`_ |

- Origin event topic0: `PaydayReceived(address,uint256,uint256)` →
  `0x026ea514fc5e4e223bbdaf9d66e602619ec85302d4740f05480dc01bb7eec65c`
- Callback proxy (Unichain Sepolia): `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4`
- Callback gas limit: 500,000 (minimum is 100,000)

## Project layout

```
src/
  PaydaySplitter.sol   # origin + destination: plans, escrow, splitPayday
  PaydayReactive.sol   # reactive: subscribes to PaydayReceived, requests callbacks
test/
  PaydaySplitter.t.sol # 12 tests: plans, escrow, split math, auth, dust
  PaydayReactive.t.sol # 7 tests incl. mock system contract (etched at 0x8888...)
script/
  deploy.sh            # raw `cast send --create` deploys (forge script can't deploy reactive contracts)
  demo.sh              # full-loop demo driver, records every tx hash to demo-log.json
```

## Run the tests

```bash
forge test
# 19 tests pass
```

## Deploy (testnet)

`forge script` cannot deploy the reactive contract — its constructor calls the
system contract, which reverts in local simulation — so deployment uses raw
creation transactions (same pattern as Lambda's `DEPLOY_TESTNET.md`).

```bash
cp .env.example .env   # DEPLOYER_PK + DEPLOYER_ADDR, mode 600, never committed
# Fund the deployer first (see below), then:
bash script/deploy.sh
bash script/demo.sh 0.05
```

### Funding the deployer (all free, testnet-only)

1. **Sepolia ETH** — any Sepolia faucet (Alchemy / QuickNode / Google Cloud).
2. **lREACT** — send Sepolia ETH to the Reactive faucet
   `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` (1 ETH → 100 lREACT,
   max 5 ETH/tx), or call `request(address)` with 0.1 ETH. Fund the reactive
   contract with ~2 lREACT at deploy; top up later with a plain transfer.
3. **Unichain Sepolia ETH** — bridge Sepolia ETH via the Unichain bridge, or
   the Uniswap faucet. Needed for the splitter deploy, the callback-gas
   float (0.02 ETH), and demo paydays.

## Demo video

`docs/demo.mp4` (< 3 min) — screen recording of the full loop: plan → payday
→ reactive transaction on Lasna → callback split on Unichain Sepolia, with
balances before/after.

## Design notes

- **Why Unichain Sepolia for both legs?** Lasna routes callbacks to Sepolia,
  Base Sepolia and Unichain Sepolia; using one chain for origin + destination
  keeps the demo (and the judges' verification) to two explorers.
- **Auth, both directions.** `react()` is `onlySystem`; `splitPayday()` only
  accepts calls from the callback proxy, and only when the injected sender
  matches the `authorizedReactive` set by the owner after deploy (the
  chicken-and-egg is solved by deploying the splitter first, then the
  reactive contract, then wiring them with `setReactive`).
- **Never reverts on the hot path.** Unmatched logs and dust fall through in
  `react()` instead of reverting — a reverting `react()` is still billed.
- **Bounded work.** One callback per payday, fixed gas limit, no loops over
  users in the split path (`withdrawSurplus` is the only O(n) view and is
  owner-only, demo-scale).

## License

MIT
