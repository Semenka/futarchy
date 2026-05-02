import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
  type Hex,
  parseUnits,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { erc20Abi, futarchyAmmAbi } from "./abi";
import { kellySize } from "./kelly";
import type { Forecast } from "./forecast";

const RPC_URL = process.env.RPC_URL ?? "http://localhost:8545";
const USDC = process.env.USDC_ADDRESS as Address;

export const pub = createPublicClient({
  chain: sepolia,
  transport: http(RPC_URL),
});

export function walletFromKey(pk: Hex) {
  const account = privateKeyToAccount(pk);
  return createWalletClient({ account, chain: sepolia, transport: http(RPC_URL) });
}

function normalize(raw: number, lo: number, hi: number): number {
  if (hi <= lo) return 0.5;
  return Math.max(0, Math.min(1, (raw - lo) / (hi - lo)));
}

async function readSpot(amm: Address): Promise<number> {
  const p = (await pub.readContract({
    address: amm,
    abi: futarchyAmmAbi,
    functionName: "getLongPrice",
  })) as bigint;
  return Number(p) / 1e18;
}

export async function tradeBranch(args: {
  wallet: ReturnType<typeof walletFromKey>;
  amm: Address;
  kpiLo: number;
  kpiHi: number;
  eKpiRaw: number;
  confidence: number;
  bankroll: bigint; // collateral units the agent will allocate at most
}): Promise<{ direction: string; collateralSpent: bigint; txHash?: Hex }> {
  const { wallet, amm, kpiLo, kpiHi, eKpiRaw, confidence, bankroll } = args;
  const eKpi = normalize(eKpiRaw, kpiLo, kpiHi);
  const spot = await readSpot(amm);
  const signal = kellySize(eKpi, spot, confidence);
  if (signal.direction === "none" || signal.fraction === 0) {
    return { direction: "none", collateralSpent: 0n };
  }

  const collateralToSpend = (bankroll * BigInt(Math.floor(signal.fraction * 10_000))) / 10_000n;
  if (collateralToSpend === 0n) return { direction: "none", collateralSpent: 0n };

  const account = wallet.account!;

  if (signal.direction === "long") {
    // approve + swap collateral -> long
    const { request: approveReq } = await pub.simulateContract({
      account,
      address: USDC,
      abi: erc20Abi,
      functionName: "approve",
      args: [amm, collateralToSpend],
    });
    const approveHash = await wallet.writeContract(approveReq);
    await pub.waitForTransactionReceipt({ hash: approveHash });

    const { request } = await pub.simulateContract({
      account,
      address: amm,
      abi: futarchyAmmAbi,
      functionName: "swapCollateralForLong",
      args: [collateralToSpend, 0n, account.address],
    });
    const txHash = await wallet.writeContract(request);
    await pub.waitForTransactionReceipt({ hash: txHash });
    return { direction: "long", collateralSpent: collateralToSpend, txHash };
  }

  // "short" path: buy SHORT cheaply by splitting collateral, selling LONG into the AMM.
  // Simplified for MVP: we skip this branch and no-op (or the user can implement).
  return { direction: "short-skipped", collateralSpent: 0n };
}
