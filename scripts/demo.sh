#!/usr/bin/env bash
# Futarchy end-to-end demo runner. Submits a grant proposal, then drives
# decide → executeBatch → resolve as each phase becomes available.
#
# Prereq: agent already running (`bun --filter agent dev`) so it picks up
# the ProposalCreated event and trades.
#
# Usage: bash scripts/demo.sh

set -euo pipefail

# ── Config (deployed Sepolia addresses) ──────────────────────────────
RPC="${RPC_URL:-https://sepolia.infura.io/v3/3b73efae86d44a67890ba58329a2fbc2}"
FACTORY="${FACTORY_ADDRESS:-0x0f1803abBa969868f9899cf7ae2491af27d104A0}"
USDC="${USDC_ADDRESS:-0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36}"
TIMELOCK="${TIMELOCK_ADDRESS:-0x4221abDD8b3196E95Ca4EAf027d7E059AA38E087}"
RESOLVER="${RESOLVER_ADDRESS:-0xE263Da1CFAD9a55ec32D2e34F1057ee272a6d5e2}"
DEPLOYER_KEY="${DEPLOYER_KEY:?DEPLOYER_KEY env required}"
GRANTEE="${GRANTEE_ADDRESS:-0x000000000000000000000000000000000000bEEF}"
GRANT_WEI="${GRANT_AMOUNT:-25000000000000000}"
TRADING_WINDOW="${TRADING_WINDOW:-180}"
OBSERVATION_BLOCKS="${OBSERVATION_BLOCKS:-2}"
KPI_HI="${KPI_HI:-100000000000000000}"
SEED="${SEED_COLLATERAL:-100000000000000000000}"

PATH="$HOME/.foundry/bin:$PATH"
export PATH

CYAN=$'\e[36m'; YEL=$'\e[33m'; GRN=$'\e[32m'; DIM=$'\e[2m'; OFF=$'\e[0m'
say() { printf "${CYAN}▌%s${OFF}\n" "$*"; }
warn() { printf "${YEL}▌%s${OFF}\n" "$*"; }
ok() { printf "${GRN}▌%s${OFF}\n" "$*"; }
banner() { printf "\n${CYAN}══════════════════════════════════════════════════════════\n  %s\n══════════════════════════════════════════════════════════${OFF}\n\n" "$*"; }

# ── 1: Submit proposal ──────────────────────────────────────────────
banner "1. Submit grant proposal"
say   "Proposal: transfer ${GRANT_WEI} wei from treasury → ${GRANTEE}"
say   "Trading window: ${TRADING_WINDOW}s · KPI: treasury ETH balance"
NEXT_ID=$(cast call "$FACTORY" "nextProposalId()(uint256)" --rpc-url "$RPC")
PROPOSAL_ID=$NEXT_ID
echo

cd "$(dirname "$0")/../contracts"
DEPLOYER_KEY="$DEPLOYER_KEY" \
FACTORY_ADDRESS="$FACTORY" \
USDC_ADDRESS="$USDC" \
TIMELOCK_ADDRESS="$TIMELOCK" \
GRANTEE_ADDRESS="$GRANTEE" \
GRANT_AMOUNT="$GRANT_WEI" \
TRADING_WINDOW="$TRADING_WINDOW" \
OBSERVATION_BLOCKS="$OBSERVATION_BLOCKS" \
KPI_HI="$KPI_HI" \
SEED_COLLATERAL="$SEED" \
forge script script/SubmitProposal.s.sol --broadcast --rpc-url "$RPC" --slow 2>&1 | grep -E "submitted|grantee|grant"
ok "Proposal id $PROPOSAL_ID created. Agent should be picking it up now."

# ── 2: Wait for trading window + agent activity ─────────────────────
banner "2. Trading window — agents forecast and trade"
say "Waiting ${TRADING_WINDOW}s for agents…"
sleep $((TRADING_WINDOW + 30))

PASS_AMM=$(cast call "$FACTORY" "getProposal(uint256)(address,address,address,bytes32,bytes32,uint256,uint256,uint256,uint256,uint8)" "$PROPOSAL_ID" --rpc-url "$RPC" | sed -n '2p')
FAIL_AMM=$(cast call "$FACTORY" "getProposal(uint256)(address,address,address,bytes32,bytes32,uint256,uint256,uint256,uint256,uint8)" "$PROPOSAL_ID" --rpc-url "$RPC" | sed -n '3p')
PASS_PRICE=$(cast call "$PASS_AMM" "getLongPrice()(uint256)" --rpc-url "$RPC")
FAIL_PRICE=$(cast call "$FAIL_AMM" "getLongPrice()(uint256)" --rpc-url "$RPC")
say "Final prices: pass=$PASS_PRICE  fail=$FAIL_PRICE"

# ── 3: decide() ─────────────────────────────────────────────────────
banner "3. decide() — read TWAPs, queue Timelock if pass > fail"
cast send "$FACTORY" "decide(uint256)" "$PROPOSAL_ID" --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" 2>&1 | grep -E "status|transactionHash" | head -2
STATE=$(cast call "$FACTORY" "getProposal(uint256)(address,address,address,bytes32,bytes32,uint256,uint256,uint256,uint256,uint8)" "$PROPOSAL_ID" --rpc-url "$RPC" | tail -1)
ok "Proposal state: $STATE  (2=DecidedPass, 3=DecidedFail)"

if [ "$STATE" != "2" ]; then
  warn "Fail branch won — no execution. Skipping to resolve."
  TIMELOCK_NEEDS_EXEC=0
else
  TIMELOCK_NEEDS_EXEC=1
fi

# ── 4: Wait for timelock + executeBatch ─────────────────────────────
if [ "$TIMELOCK_NEEDS_EXEC" = "1" ]; then
  banner "4. Wait for timelock delay (5 min) + executeBatch"
  say "Polling timelock readiness…"
  # Compute op id from getExecutionPayload + factory salt
  PAYLOAD=$(cast call "$FACTORY" "getExecutionPayload(uint256)(address[],uint256[],bytes[],bytes32)" "$PROPOSAL_ID" --rpc-url "$RPC")
  TARGETS=$(echo "$PAYLOAD" | sed -n '1p')
  VALUES=$(echo "$PAYLOAD" | sed -n '2p')
  DATAS=$(echo "$PAYLOAD" | sed -n '3p')
  SALT=$(echo "$PAYLOAD" | sed -n '4p')
  # hashOperationBatch(targets, values, payloads, predecessor, salt)
  OP_ID=$(cast call "$TIMELOCK" "hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)(bytes32)" "$TARGETS" "$VALUES" "$DATAS" 0x0000000000000000000000000000000000000000000000000000000000000000 "$SALT" --rpc-url "$RPC")
  say "Operation id: $OP_ID"
  while true; do
    R=$(cast call "$TIMELOCK" "isOperationReady(bytes32)(bool)" "$OP_ID" --rpc-url "$RPC" 2>/dev/null || true)
    [ "$R" = "true" ] && break
    printf "${DIM}.${OFF}"; sleep 20
  done
  echo
  ok "Timelock ready. Executing batch."
  cast send "$TIMELOCK" "executeBatch(address[],uint256[],bytes[],bytes32,bytes32)" "$TARGETS" "$VALUES" "$DATAS" 0x0000000000000000000000000000000000000000000000000000000000000000 "$SALT" --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" 2>&1 | grep -E "status|transactionHash" | head -2
  TBAL=$(cast balance "$TIMELOCK" --ether --rpc-url "$RPC")
  GBAL=$(cast balance "$GRANTEE" --ether --rpc-url "$RPC")
  ok "Treasury balance: $TBAL ETH · grantee balance: $GBAL ETH"
fi

# ── 5: Wait for observation block + resolve ─────────────────────────
banner "5. Wait for observation block + resolve()"
OBS_BLOCK=$(cast call "$FACTORY" "getKPIConfig(uint256)(address,address,uint256,uint256,uint256,uint8)" "$PROPOSAL_ID" --rpc-url "$RPC" | sed -n '3p' | awk '{print $1}')
say "Observation block: $OBS_BLOCK · waiting for chain to advance…"
while true; do
  CUR=$(cast block-number --rpc-url "$RPC")
  [ "$CUR" -ge "$OBS_BLOCK" ] && break
  printf "${DIM}.${OFF}"; sleep 12
done
echo
ok "Block reached. Resolving."
cast send "$RESOLVER" "resolve(uint256)" "$PROPOSAL_ID" --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" 2>&1 | grep -E "status|transactionHash" | head -2
STATE=$(cast call "$FACTORY" "getProposal(uint256)(address,address,address,bytes32,bytes32,uint256,uint256,uint256,uint256,uint8)" "$PROPOSAL_ID" --rpc-url "$RPC" | tail -1)
ok "Final state: $STATE  (4=Resolved)"

banner "✓ Demo complete. Open localhost:3000/leaderboard to see Brier scores."
