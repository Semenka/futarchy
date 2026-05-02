# futarchy

Vote values, bet beliefs.

A toy DAO governance module where every proposal spawns two conditional prediction markets — one for **IF-pass**, one for **IF-fail** — on a measurable KPI (e.g., the treasury's ETH balance at block N). AI traders forecast and trade both branches. Whichever branch prices the KPI higher auto-executes via an OpenZeppelin Timelock.

Maps 1-to-1 to Vitalik's Nov 2024 [*From prediction markets to info finance*](https://vitalik.eth.limo/general/2024/11/27/info_finance.html). MetaDAO is the only live futarchy on Solana — this is a Sepolia EVM analogue.

📹 **[Demo video (4:12)](https://github.com/Semenka/futarchy/releases/download/v0.1.0/futarchy_demo.mp4)** — live walkthrough on Sepolia.

## Architecture

| Layer | Stack |
|---|---|
| Contracts | Foundry · Solidity 0.8.26 · OpenZeppelin v5 |
| Agent | TypeScript · viem · Bun · Google Gemini 2.5 Flash |
| Frontend | Next.js 15 · Tailwind · server-rendered, client-polled |
| Network | Ethereum Sepolia |

```
proposal ──► ProposalFactory
              ├─ prepareCondition × 2  (BCT)
              ├─ deploy AMM × 2        (FutarchyAMM, V2 fork + TWAP)
              └─ seed liquidity        (neutral 0.5 prior, both branches)

        agents trade both branches
              │
              ▼
        decide()  ──TWAP[pass] > TWAP[fail]?──► Timelock.scheduleBatch
                                       no?    ──► no execution

        Timelock delay → executeBatch → action lands

        observation block → Resolver.resolve()
              ├─ read KPI from chain
              ├─ winning branch  → scalar payout numerators
              └─ losing branch   → void (5000/5000) at half collateral
```

## Sepolia deployment

| Contract | Address |
|---|---|
| fUSDC (collateral) | [`0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36`](https://sepolia.etherscan.io/address/0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36) |
| BinaryConditionalTokens | [`0x39bee52D05bcD3F58C023718C5be1B7908B1C929`](https://sepolia.etherscan.io/address/0x39bee52D05bcD3F58C023718C5be1B7908B1C929) |
| Timelock (treasury) | [`0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087`](https://sepolia.etherscan.io/address/0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087) |
| ProposalFactory | [`0x0f1803abBa969868f9899cf7ae2491af27d104A0`](https://sepolia.etherscan.io/address/0x0f1803abBa969868f9899cf7ae2491af27d104A0) |
| Resolver | [`0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2`](https://sepolia.etherscan.io/address/0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2) |

Two proposals have run end-to-end against this deploy. See [`demo/README.md`](demo/README.md) for the full tx-hash table.

## Run it

```bash
# 1. Compile + test contracts (256-run fuzz invariant included)
( cd contracts && forge test )

# 2. Install workspace deps
bun install

# 3. Configure agent
cp agent/.env.example agent/.env
# Add: GEMINI_API_KEY, RPC_URL, three persona PKs, deployed addresses

# 4. Configure frontend
cp frontend/.env.example frontend/.env.local
# Add: NEXT_PUBLIC_RPC_URL, NEXT_PUBLIC_FACTORY_ADDRESS

# 5. Boot
bun --filter agent dev          # terminal 1: watches for ProposalCreated
bun --filter frontend dev       # terminal 2: localhost:3000

# 6. Submit a demo proposal end-to-end
DEPLOYER_KEY=0x... bash scripts/demo.sh
```

## Repo layout

- `contracts/` — Foundry sources, tests, deploy + submit scripts
- `agent/` — viem event watcher, Gemini forecasting, Kelly sizing, three personas
- `frontend/` — Next.js read-only viewer with live prices, countdown, leaderboard
- `scripts/demo.sh` — end-to-end orchestrator that runs a proposal lifecycle
- `demo/` — recording + tx-hash audit trail
- `RECORDING.md` — guide for recording a clean demo video

## Design decisions

The full plan and architectural rationale live at `~/.claude/plans/delegated-mapping-riddle.md`. Two notable simplifications for the 48h MVP:

1. **Custom minimal binary CT** instead of Gnosis Conditional Token Framework. CTF is on Solidity 0.5, incompatible with our 0.8 OZ Timelock. Interface mirrors CTF so swap-in later is mechanical.
2. **Losing branch resolves to 0.5/0.5 (void)**, not full parity refund. True futarchy would CT-nest pass/fail above the KPI condition; we use two independent scalar conditions. Decision mechanic is intact.

## License

MIT.
