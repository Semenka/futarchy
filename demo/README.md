# Demo recording

`futarchy_demo.mp4` — 4 minute, 1080p screen capture of the futarchy stack
running live on Ethereum Sepolia.

## What's captured
- Next.js frontend at localhost:3000 showing the running deploy
- Proposal #0 in `Resolved` state from the earlier full-lifecycle smoke test
- Live trading: proposal #1 submitted with 75s window
- Gemini-driven Contrarian-Claude finds mispricing, pushes pass-LONG to 1.05
- `decide()` lands → `DecidedPass` (TWAP 0.755 vs 0.5) → batch queued in
  Timelock

## What's not captured (cut for length)
- 5-minute Timelock delay between `decide()` and `executeBatch()`
- `executeBatch()` (already verified for proposal #0; reuse those tx hashes)
- `resolve()` and final Brier-score update

For a complete end-to-end without cuts, run `scripts/demo.sh` and record
yourself; total runtime ~7 min.

## Sepolia deployment

| Contract | Address |
|---|---|
| fUSDC | `0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36` |
| BCT | `0x39bee52D05bcD3F58C023718C5be1B7908B1C929` |
| Timelock (treasury) | `0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087` |
| ProposalFactory | `0x0f1803abBa969868f9899cf7ae2491af27d104A0` |
| Resolver | `0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2` |

## Proposal #0 lifecycle proof (full end-to-end on chain)

| Phase | Tx hash |
|---|---|
| Bullish trade | `0xb2a10cc0b11aadff4173608fa4b5f9fa244cb988eb69a798d85319bd278358a3` |
| `decide(0)` | `0x7db7b2d4a93987624cf01c2bdd7b6af07239b155d690bceb0e417dee1257eeea` |
| `executeBatch` | `0xac31fd5d4dd668971788296ac2bf514e8946bdfaee285500c9aca779e7061a34` |
| `resolve(0)` | `0x7863a323feabd839c1467cc1fd6e166e4e78d2d8d64eafe9ac30ba9309ee18e9` |

## Proposal #1 trades (in this recording)

| Phase | Tx hash |
|---|---|
| `decide(1)` | `0xae9a19fe086b1ea99abaa8249585b0085659fae520285cbfe6be3246bfd46571` |
