import { type Address, formatUnits, parseAbiItem } from "viem";
import { client } from "./client";
import { proposalFactoryAbi, bctAbi } from "./abi";
import { PERSONAS } from "./personas";

const SWAP_EVENT = parseAbiItem(
  "event Swap(address indexed sender, address indexed to, uint256 collateralIn, uint256 longIn, uint256 collateralOut, uint256 longOut)",
);
const SYNC_EVENT = parseAbiItem("event Sync(uint112 reserveCollateral, uint112 reserveLong)");

const BCT_ADDRESS = "0x39bee52D05bcD3F58C023718C5be1B7908B1C929" as const;

export interface PersonaScore {
  personaId: string;
  label: string;
  address: Address;
  trades: number;
  fUsdcBalance: number;
  brierSum: number;
  brierCount: number;
  avgBrier: number | null;
}

export interface ResolvedSummary {
  proposalId: bigint;
  passActual: number; // post-resolution numerator1 / denom for pass
  failActual: number;
}

interface ProposalRow {
  id: bigint;
  passAMM: Address;
  failAMM: Address;
  passConditionId: `0x${string}`;
  failConditionId: `0x${string}`;
  state: number;
}

const STATE_RESOLVED = 4;

async function listProposals(factory: Address): Promise<ProposalRow[]> {
  const next = (await client.readContract({
    address: factory,
    abi: proposalFactoryAbi,
    functionName: "nextProposalId",
  })) as bigint;

  const out: ProposalRow[] = [];
  for (let i = 0n; i < next; i++) {
    const r = (await client.readContract({
      address: factory,
      abi: proposalFactoryAbi,
      functionName: "getProposal",
      args: [i],
    })) as [Address, Address, Address, `0x${string}`, `0x${string}`, bigint, bigint, bigint, bigint, number];
    out.push({
      id: i,
      passAMM: r[1],
      failAMM: r[2],
      passConditionId: r[3],
      failConditionId: r[4],
      state: Number(r[9]),
    });
  }
  return out;
}

async function readActuals(passConditionId: `0x${string}`, failConditionId: `0x${string}`) {
  const [pass, fail] = await Promise.all([
    client.readContract({
      address: BCT_ADDRESS,
      abi: bctAbi,
      functionName: "conditions",
      args: [passConditionId],
    }),
    client.readContract({
      address: BCT_ADDRESS,
      abi: bctAbi,
      functionName: "conditions",
      args: [failConditionId],
    }),
  ]);
  // tuple: [oracle, questionId, resolved, num0, num1, denom]
  const passActual = Number(pass[4]) / Number(pass[5]);
  const failActual = Number(fail[4]) / Number(fail[5]);
  return { passActual, failActual };
}

/**
 * Each persona's "implied forecast" for a branch is the spot price after their
 * last trade on that branch's AMM. We approximate by reading post-trade reserves
 * from the Sync event that immediately follows their Swap.
 */
async function lastImpliedPrice(amm: Address, persona: Address, fromBlock: bigint): Promise<number | null> {
  const swaps = await client.getLogs({
    address: amm,
    event: SWAP_EVENT,
    args: { sender: persona },
    fromBlock,
    toBlock: "latest",
  });
  if (swaps.length === 0) return null;
  const lastSwap = swaps[swaps.length - 1]!;

  const syncs = await client.getLogs({
    address: amm,
    event: SYNC_EVENT,
    fromBlock: lastSwap.blockNumber,
    toBlock: lastSwap.blockNumber,
  });
  const matching = syncs.find(
    (s) => s.transactionHash === lastSwap.transactionHash && (s.logIndex ?? 0) >= (lastSwap.logIndex ?? 0),
  );
  if (!matching) return null;
  const { reserveCollateral, reserveLong } = matching.args;
  if (!reserveCollateral || !reserveLong) return null;
  if (reserveLong === 0n) return null;
  return Number((reserveCollateral * 10n ** 18n) / reserveLong) / 1e18;
}

export async function computeLeaderboard(factory: Address): Promise<{
  personas: PersonaScore[];
  resolved: ResolvedSummary[];
}> {
  const proposals = await listProposals(factory);
  const fromBlock = 0n; // small history; for production paginate

  const usdcAddress = "0x1D8866ed12fe4C189BDc55A68ED5280DA2BD3F36" as Address;
  const usdcAbi = [
    {
      type: "function" as const,
      name: "balanceOf",
      stateMutability: "view" as const,
      inputs: [{ name: "owner", type: "address" as const }],
      outputs: [{ type: "uint256" as const }],
    },
  ];

  const balances = await Promise.all(
    PERSONAS.map((p) =>
      client.readContract({ address: usdcAddress, abi: usdcAbi, functionName: "balanceOf", args: [p.address] }),
    ),
  );

  const personaScores: PersonaScore[] = PERSONAS.map((p, i) => ({
    personaId: p.id,
    label: p.label,
    address: p.address,
    trades: 0,
    fUsdcBalance: Number(formatUnits(balances[i] as bigint, 18)),
    brierSum: 0,
    brierCount: 0,
    avgBrier: null,
  }));

  const resolved: ResolvedSummary[] = [];

  for (const proposal of proposals) {
    if (proposal.state !== STATE_RESOLVED) continue;
    const { passActual, failActual } = await readActuals(proposal.passConditionId, proposal.failConditionId);
    resolved.push({ proposalId: proposal.id, passActual, failActual });

    for (const score of personaScores) {
      const passImplied = await lastImpliedPrice(proposal.passAMM, score.address, fromBlock);
      const failImplied = await lastImpliedPrice(proposal.failAMM, score.address, fromBlock);
      if (passImplied !== null) {
        score.trades += 1;
        score.brierSum += (passImplied - passActual) ** 2;
        score.brierCount += 1;
      }
      if (failImplied !== null) {
        score.trades += 1;
        score.brierSum += (failImplied - failActual) ** 2;
        score.brierCount += 1;
      }
    }
  }
  for (const s of personaScores) {
    s.avgBrier = s.brierCount > 0 ? s.brierSum / s.brierCount : null;
  }
  return { personas: personaScores, resolved };
}
