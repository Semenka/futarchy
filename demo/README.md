# Demo recording

`futarchy_demo.mp4` — **3-minute narrated walk-through** of the futarchy stack
running live on Ethereum Sepolia.

- 1280 × 720 (720p), 30 fps, h.264 video + AAC narration
- 4.0 MB
- Cropped to the app interface only — no editor windows
- Voiceover (Samantha, macOS `say`) covers project description, on-screen demo, and how it's built

Hackathon submission asset attached at:
**https://github.com/Semenka/futarchy/releases/tag/v0.1.0**

## Narration outline

| Time | Section |
|---|---|
| 0:00 – 0:35 | **What and why** — Hanson's "vote on values, bet on beliefs"; Vitalik's info finance post; MetaDAO on Solana |
| 0:35 – 1:50 | **Demonstration** — what's on screen, two markets per proposal, Gemini traders + Kelly sizing, decide → Timelock → execute → resolve |
| 1:50 – 2:55 | **How it's built** — 5 Solidity contracts, Foundry tests, TypeScript+viem agent, Next.js frontend |

## What's on screen

The Next.js read-only viewer at `localhost:3000` showing the live deploy.
Both proposals are in `Resolved` state — the IF-pass branches highlighted
green because the market correctly directed the proposals to execute.

## Sepolia deployment

| Contract | Address |
|---|---|
| fUSDC (collateral) | `0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36` |
| BinaryConditionalTokens | `0x39bee52D05bcD3F58C023718C5be1B7908B1C929` |
| Timelock (treasury) | `0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087` |
| ProposalFactory | `0x0f1803abBa969868f9899cf7ae2491af27d104A0` |
| Resolver | `0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2` |

## Tx hashes (verifiable on Sepolia Etherscan)

### Proposal #0 — full lifecycle
| Phase | Hash |
|---|---|
| Bullish trade | `0xb2a10cc0b11aadff4173608fa4b5f9fa244cb988eb69a798d85319bd278358a3` |
| `decide(0)` | `0x7db7b2d4a93987624cf01c2bdd7b6af07239b155d690bceb0e417dee1257eeea` |
| `executeBatch` | `0xac31fd5d4dd668971788296ac2bf514e8946bdfaee285500c9aca779e7061a34` |
| `resolve(0)` | `0x7863a323feabd839c1467cc1fd6e166e4e78d2d8d64eafe9ac30ba9309ee18e9` |

### Proposal #1 — full lifecycle
| Phase | Hash |
|---|---|
| `decide(1)` | `0xae9a19fe086b1ea99abaa8249585b0085659fae520285cbfe6be3246bfd46571` |
| `executeBatch` | `0x53608cbc0f27fe2e6ba4d64163daf593ec5d2f8af22d2e08159858f8ebf0c3be` |
| `resolve(1)` | `0x9c82b60bde52bf49f537c85762a1a1a0c7a0c23436628e8e24fca95bf685ae49` |

The mp4 is gitignored (4.0 MB). Open with `open demo/futarchy_demo.mp4` or grab from
the GitHub release.
