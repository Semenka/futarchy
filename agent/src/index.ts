import "dotenv/config";
import { type Address, type Hex, parseUnits, formatUnits } from "viem";
import { proposalFactoryAbi, futarchyAmmAbi, erc20Abi } from "./abi";
import { PERSONAS } from "./personas";
import { forecast, type ProposalContext } from "./forecast";
import { pub, walletFromKey, tradeBranch } from "./trade";

const FACTORY = process.env.FACTORY_ADDRESS as Address;
const USDC = process.env.USDC_ADDRESS as Address;

const KEYS: Record<string, Hex> = {
  bullish: process.env.BULLISH_KEY as Hex,
  bearish: process.env.BEARISH_KEY as Hex,
  contrarian: process.env.CONTRARIAN_KEY as Hex,
};

const BANKROLL = parseUnits("1000", 18); // 1000 fUSDC per persona

async function handleProposal(proposalId: bigint) {
  const [, passAMM, failAMM, , , , , kpiLo, kpiHi] = (await pub.readContract({
    address: FACTORY,
    abi: proposalFactoryAbi,
    functionName: "getProposal",
    args: [proposalId],
  })) as [Address, Address, Address, Hex, Hex, bigint, bigint, bigint, bigint, number];

  const [, values, , ] = (await pub.readContract({
    address: FACTORY,
    abi: proposalFactoryAbi,
    functionName: "getExecutionPayload",
    args: [proposalId],
  })) as [Address[], bigint[], Hex[], Hex];

  const passSpot = (await pub.readContract({
    address: passAMM,
    abi: futarchyAmmAbi,
    functionName: "getLongPrice",
  })) as bigint;
  const failSpot = (await pub.readContract({
    address: failAMM,
    abi: futarchyAmmAbi,
    functionName: "getLongPrice",
  })) as bigint;

  const ctx: ProposalContext = {
    proposalId,
    txSummary: `Execute ${values.length} transaction(s); total ETH value ${formatUnits(
      values.reduce((a, b) => a + b, 0n),
      18,
    )} ETH`,
    kpiDescription: "DAO treasury ETH balance at the observation block",
    kpiLo: Number(formatUnits(kpiLo, 18)),
    kpiHi: Number(formatUnits(kpiHi, 18)),
    currentPassPrice: Number(passSpot) / 1e18,
    currentFailPrice: Number(failSpot) / 1e18,
    treasuryBalanceNow: 100, // TODO: read from chain in v2
  };

  for (const p of PERSONAS) {
    const pk = KEYS[p.id];
    if (!pk) {
      console.log(`[${p.label}] missing key; skipping`);
      continue;
    }
    try {
      const fc = await forecast(p, ctx);
      console.log(`[${p.label}] forecast:`, fc);

      const wallet = walletFromKey(pk);
      const passResult = await tradeBranch({
        wallet,
        amm: passAMM,
        kpiLo: ctx.kpiLo,
        kpiHi: ctx.kpiHi,
        eKpiRaw: fc.eKpiPass,
        confidence: fc.confidence,
        bankroll: BANKROLL,
      });
      const failResult = await tradeBranch({
        wallet,
        amm: failAMM,
        kpiLo: ctx.kpiLo,
        kpiHi: ctx.kpiHi,
        eKpiRaw: fc.eKpiFail,
        confidence: fc.confidence,
        bankroll: BANKROLL,
      });
      console.log(`[${p.label}] pass:`, passResult, "fail:", failResult);
    } catch (e) {
      console.error(`[${p.label}] error:`, e);
    }
  }
}

async function main() {
  if (!FACTORY || !USDC) {
    console.error("set FACTORY_ADDRESS and USDC_ADDRESS in .env");
    process.exit(1);
  }

  console.log("futarchy agent: watching factory", FACTORY);

  pub.watchContractEvent({
    address: FACTORY,
    abi: proposalFactoryAbi,
    eventName: "ProposalCreated",
    onLogs: async (logs) => {
      for (const log of logs) {
        const id = log.args.proposalId!;
        console.log("ProposalCreated:", id.toString());
        try {
          await handleProposal(id);
        } catch (e) {
          console.error("handleProposal error:", e);
        }
      }
    },
    onError: (e) => console.error("watch error:", e),
  });

  // keep the process alive
  await new Promise(() => {});
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
