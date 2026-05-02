# Futarchy Toy DAO — Hackathon Submission

> "Vote values, bet beliefs." — Robin Hanson, 2000

## Problem

DAO governance today is voting. Token holders cast yes/no on proposals based on opinion, lobbying, and tribal alignment. Markets, by contrast, aggregate dispersed information into a single price. Governance leaves that price-discovery on the table.

Vitalik's Nov 2024 *From prediction markets to info finance* makes the case that conditional prediction markets — where each branch prices a measurable outcome — should drive treasury decisions. **MetaDAO** runs futarchy on Solana. Nothing production-grade exists on Ethereum.

## Solution

Every proposal spawns two scalar prediction markets:

- **IF-pass** — what will the KPI (e.g., treasury balance after N blocks) be if this proposal executes?
- **IF-fail** — what will it be if it doesn't?

AI traders — Claude, Gemini, GPT, whatever — forecast both branches independently and trade through a constant-product AMM. When the trading window closes, whichever branch's TWAP priced the KPI higher wins. **That branch's calldata enters an OpenZeppelin TimelockController and executes on chain.** No human votes; the market decides.

After execution, an oracle reads the actual KPI value and pays out the winning market at the realized normalized score. The losing branch voids at half collateral. Brier scores against realized outcomes rank the traders.

## What's built

| Component | Status |
|---|---|
| 5 Solidity contracts (BCT, ERC1155Wrapper, FutarchyAMM, ProposalFactory, Resolver) | ✅ deployed on Sepolia |
| 6 Foundry tests + 256-run fuzz invariant on `passPrice > failPrice ⇒ executes` | ✅ passing |
| 3-persona Gemini agent (Bullish / Bearish / Contrarian) with Kelly sizing | ✅ live |
| Next.js read-only frontend with live AMM prices, countdown, Brier-score leaderboard | ✅ live |
| End-to-end orchestrator (`scripts/demo.sh`) | ✅ |
| Two complete proposal lifecycles on Sepolia (propose → trade → decide → execute → resolve) | ✅ verifiable on-chain |

## Demo

📹 **`demo/futarchy_demo.mp4`** — narrated 50-second walk-through.
Also attached as a GitHub Release asset:
**https://github.com/Semenka/futarchy/releases/tag/v0.1.0**

## Architecture

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
              └─ losing branch   → void (5000/5000)
```

## Proof of working system

Sepolia chain ID 11155111. All addresses verified.

| Contract | Address |
|---|---|
| fUSDC (collateral) | [`0x1D8866ed...3F36`](https://sepolia.etherscan.io/address/0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36) |
| BinaryConditionalTokens | [`0x39bee52D...C929`](https://sepolia.etherscan.io/address/0x39bee52D05bcD3F58C023718C5be1B7908B1C929) |
| Timelock (treasury) | [`0x4221abDD...E087`](https://sepolia.etherscan.io/address/0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087) |
| ProposalFactory | [`0x0f1803ab...04A0`](https://sepolia.etherscan.io/address/0x0f1803abBa969868f9899cf7ae2491af27d104A0) |
| Resolver | [`0xE263Da1C...d5e2`](https://sepolia.etherscan.io/address/0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2) |

### Proposal #0 — full lifecycle
| Phase | Tx |
|---|---|
| Bullish trade | [`0xb2a10cc0…8358a3`](https://sepolia.etherscan.io/tx/0xb2a10cc0b11aadff4173608fa4b5f9fa244cb988eb69a798d85319bd278358a3) |
| `decide(0)` | [`0x7db7b2d4…57eea`](https://sepolia.etherscan.io/tx/0x7db7b2d4a93987624cf01c2bdd7b6af07239b155d690bceb0e417dee1257eeea) |
| `executeBatch` | [`0xac31fd5d…061a34`](https://sepolia.etherscan.io/tx/0xac31fd5d4dd668971788296ac2bf514e8946bdfaee285500c9aca779e7061a34) |
| `resolve(0)` | [`0x7863a323…e18e9`](https://sepolia.etherscan.io/tx/0x7863a323feabd839c1467cc1fd6e166e4e78d2d8d64eafe9ac30ba9309ee18e9) |

### Proposal #1 — full lifecycle
| Phase | Tx |
|---|---|
| `decide(1)` | [`0xae9a19fe…d46571`](https://sepolia.etherscan.io/tx/0xae9a19fe086b1ea99abaa8249585b0085659fae520285cbfe6be3246bfd46571) |
| `executeBatch` | [`0x53608cbc…bf0c3be`](https://sepolia.etherscan.io/tx/0x53608cbc0f27fe2e6ba4d64163daf593ec5d2f8af22d2e08159858f8ebf0c3be) |
| `resolve(1)` | [`0x9c82b60b…685ae49`](https://sepolia.etherscan.io/tx/0x9c82b60bde52bf49f537c85762a1a1a0c7a0c23436628e8e24fca95bf685ae49) |

## Tech stack

- **Solidity 0.8.26** + OpenZeppelin v5 (Timelock, ERC1155, ERC20, ReentrancyGuard, AccessControl)
- **Foundry** for build, fuzz, and broadcast
- **TypeScript + viem + Bun** for the trading agent
- **Google Gemini 2.5 Flash** with structured-output schema for forecasts
- **Next.js 15 + Tailwind** for the frontend
- **Ethereum Sepolia** as the live target

## Why this fits the theme

- Maps directly to **Vitalik's most-tweeted unbuilt idea** in 2024
- AI agents are first-class market participants — the cryptoeconomic primitive, not bolted on
- Live, visible, verifiable — every claim above has an on-chain transaction hash
- Real cryptoeconomic substance: scalar conditional tokens, AMM TWAPs, oracles, timelock governance

## Limits + honest call-outs

For the 48-hour MVP we cut:

1. **Custom minimal binary CT** instead of canonical Gnosis CTF (CTF is on Solidity 0.5; would have cost 2-3h of dual-solc plumbing). Interface mirrors CTF so a swap-in is mechanical.
2. **Losing branch voids at 0.5/0.5**, not full parity refund. Proper futarchy nests pass/fail above the KPI condition; we use two independent scalar conditions. Decision mechanic is intact, redemption math differs.
3. **Short side unimplemented** in the agent (would need split + sell-long flow). In the demo, only the long side trades; this still produces correct decisions when at least one persona disagrees with the spot price (Bullish in proposal #0, Contrarian in proposal #1).
4. **No LP fees**, single proposal template (`transfer(amount, recipient)`), three seeded personas only.

## Repository

**https://github.com/Semenka/futarchy** (public)

Run it yourself:

```bash
git clone https://github.com/Semenka/futarchy
cd futarchy
( cd contracts && forge test )
bun install
# fill in agent/.env and frontend/.env.local
bun --filter agent dev      # terminal 1
bun --filter frontend dev   # terminal 2
DEPLOYER_KEY=0x... bash scripts/demo.sh   # terminal 3
```
