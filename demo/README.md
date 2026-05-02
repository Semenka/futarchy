# Demo recording

`futarchy_demo.mp4` — 4 minute 12 second screen capture of the futarchy stack
running live on Ethereum Sepolia.

## What's captured

- Next.js frontend at localhost:3000 showing the running deploy
- Proposal #0 (already `Resolved` from earlier full-lifecycle smoke test)
- Live submission of proposal #1 with 75s trading window
- Gemini-driven Contrarian-Claude finds mispricing, pushes pass-LONG to 1.05
- `decide(1)` → `DecidedPass` (TWAP 0.755 vs 0.5) → batch queued in Timelock
- Final 12s tail: both proposals shown as `Resolved`, IF-PASS branches
  highlighted in green

## End-to-end timing in the recording

| t (~) | Event |
|---|---|
| 0:00 | Frontend loaded, proposal #0 visible (Resolved) |
| 0:30 | `createProposal` for #1 broadcast |
| 1:00–2:30 | Agent backfills, Gemini forecasts arrive, Contrarian goes long |
| 2:30 | Trading window expires |
| 3:00 | `decide(1)` → DecidedPass |
| 3:00–4:00 | (Off-screen: Timelock + executeBatch + resolve, completed after recording) |
| 4:00–4:12 | Final state — both proposals Resolved |

## Sepolia deployment

| Contract | Address |
|---|---|
| fUSDC | `0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36` |
| BCT | `0x39bee52D05bcD3F58C023718C5be1B7908B1C929` |
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

### Proposal #1 — full lifecycle (the one in the recording)
| Phase | Hash |
|---|---|
| `decide(1)` | `0xae9a19fe086b1ea99abaa8249585b0085659fae520285cbfe6be3246bfd46571` |
| `executeBatch` | `0x53608cbc0f27fe2e6ba4d64163daf593ec5d2f8af22d2e08159858f8ebf0c3be` |
| `resolve(1)` | `0x9c82b60bde52bf49f537c85762a1a1a0c7a0c23436628e8e24fca95bf685ae49` |

## How to play

The file is gitignored (16MB). It lives at `demo/futarchy_demo.mp4`. Open
in QuickTime, VLC, or upload directly to YouTube / hackathon submission.
