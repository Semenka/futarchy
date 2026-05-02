# Demo Recording Guide

End-to-end demo runtime is ~7 minutes (5 of those are timelock delay). Plan to edit
the timelock wait down to ~10s in post.

## Pre-flight (do once)

```bash
# 1. install foundry, bun, node — already done if you ran the build
# 2. install workspace deps
bun install
# 3. compile + test contracts
( cd contracts && forge test )
# 4. confirm env files are populated
cat agent/.env       # GEMINI_API_KEY + 3 persona keys + addresses
cat frontend/.env.local
```

## Live deployment (Sepolia)

| | Address |
|---|---|
| fUSDC | `0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36` |
| BCT | `0x39bee52D05bcD3F58C023718C5be1B7908B1C929` |
| Timelock (treasury) | `0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087` |
| ProposalFactory | `0x0f1803abBa969868f9899cf7ae2491af27d104A0` |
| Resolver | `0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2` |

## Recording layout

Three windows side-by-side make the best demo:

1. **Browser** at `http://localhost:3000` — frontend with proposal cards
2. **Terminal A** — the agent (`bun --filter agent dev`), shows forecasts and trades
3. **Terminal B** — the demo orchestrator (runs `scripts/demo.sh`)

## Recording steps

1. **Start QuickTime Player → File → New Screen Recording.** Pick the area covering the three windows.
2. Hit record.
3. In Terminal A: start the agent.
   ```bash
   bun --filter agent dev
   ```
4. In Terminal B: run the demo orchestrator.
   ```bash
   DEPLOYER_KEY=0x3601904e47a50151c809e3ea4bb0bb6c848bef5337e15f34f545f6f5e5a5c524 \
     bash scripts/demo.sh
   ```
5. The script handles: proposal submission → trading window → decide → timelock → executeBatch → resolve.
6. Browser will auto-refresh every 5s — viewers watch the proposal card flip from "decide in mm:ss" to "PASS queued" to "Resolved", and the leaderboard populate.
7. Stop recording.

## Edit checklist

- Cut the 5min timelock wait down to a "fast forward" or fade.
- Cut any 30s polling loops (they print dots — easy to splice).
- Add titles for each phase (matches the `banner` lines in `demo.sh`).
- Highlight the moment pass-branch price diverges in the browser.

## Demo narration cues

- "DAO has 0.05 ETH. Someone proposes a 0.025 ETH grant."
- "Two markets spawn — IF-pass and IF-fail. Both start at neutral 0.5 prior."
- "Three Gemini-powered traders forecast. Bullish thinks the grant grows the treasury — buys long on pass. Bearish and Contrarian think it depletes — would short pass."
- "Pass branch's TWAP comes in higher than fail's. Decide() queues the Timelock batch."
- "Five-minute timelock delay" — fade.
- "ExecuteBatch fires — 0.025 ETH moves from treasury to grantee."
- "Resolver reads the post-execution treasury balance, reports BCT payouts, void on the losing fail branch."
- "Leaderboard updates: Brier score = (forecast − actual)²."

## What's NOT in the recording (out-of-scope)

- Bearish/Contrarian don't actually trade (short side skipped in MVP). Mention this as a TODO during narration if you want.
- LP fees disabled.
- Single proposal template (transfer-only).
- Treasury stays at 0.05 ETH base across runs — submit multiple proposals to see the leaderboard accumulate.
