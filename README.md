# futarchy

Toy DAO futarchy: every proposal spawns two conditional prediction markets (IF-pass / IF-fail) on a KPI. AI agents trade them. Whichever branch prices the KPI higher auto-executes via timelock.

## Layout

- `contracts/` — Foundry. Factory, conditional AMMs, resolver, timelock. Gnosis CTF vendored as submodule.
- `agent/` — TypeScript. viem event watcher + Claude traders (3 personas) + Kelly sizing.
- `frontend/` — Next.js + wagmi. Proposal feed, live branch prices, agent leaderboard.

## Target network

Base Sepolia.

## Commands

```bash
# contracts
cd contracts && forge build && forge test

# agent (from repo root)
bun --filter agent dev

# frontend (from repo root)
bun --filter frontend dev
```
