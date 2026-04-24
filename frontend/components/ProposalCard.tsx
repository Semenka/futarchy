"use client";
import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { client } from "@/lib/client";
import { proposalFactoryAbi, futarchyAmmAbi } from "@/lib/abi";

type State = "None" | "Trading" | "DecidedPass" | "DecidedFail" | "Resolved";
const STATE_LABEL: State[] = ["None", "Trading", "DecidedPass", "DecidedFail", "Resolved"];

interface Proposal {
  id: bigint;
  proposer: `0x${string}`;
  passAMM: `0x${string}`;
  failAMM: `0x${string}`;
  tradingDeadline: bigint;
  kpiLo: bigint;
  kpiHi: bigint;
  state: number;
}

export function ProposalCard({ factory, id }: { factory: `0x${string}`; id: bigint }) {
  const [p, setP] = useState<Proposal | null>(null);
  const [passPrice, setPassPrice] = useState<number | null>(null);
  const [failPrice, setFailPrice] = useState<number | null>(null);
  const [now, setNow] = useState<number>(() => Math.floor(Date.now() / 1000));

  useEffect(() => {
    let live = true;
    async function load() {
      const r = await client.readContract({
        address: factory,
        abi: proposalFactoryAbi,
        functionName: "getProposal",
        args: [id],
      });
      if (!live) return;
      const proposal: Proposal = {
        id,
        proposer: r[0] as `0x${string}`,
        passAMM: r[1] as `0x${string}`,
        failAMM: r[2] as `0x${string}`,
        tradingDeadline: r[5] as bigint,
        kpiLo: r[7] as bigint,
        kpiHi: r[8] as bigint,
        state: Number(r[9]),
      };
      setP(proposal);

      const [pp, fp] = await Promise.all([
        client.readContract({ address: proposal.passAMM, abi: futarchyAmmAbi, functionName: "getLongPrice" }),
        client.readContract({ address: proposal.failAMM, abi: futarchyAmmAbi, functionName: "getLongPrice" }),
      ]);
      if (!live) return;
      setPassPrice(Number(pp) / 1e18);
      setFailPrice(Number(fp) / 1e18);
    }
    load().catch(console.error);
    const iv = setInterval(() => load().catch(console.error), 5000);
    const tick = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => {
      live = false;
      clearInterval(iv);
      clearInterval(tick);
    };
  }, [factory, id]);

  if (!p) {
    return <div className="p-4 border border-neutral-800 rounded">Loading #{id.toString()}…</div>;
  }

  const remaining = Number(p.tradingDeadline) - now;
  const mm = Math.max(0, Math.floor(remaining / 60));
  const ss = String(Math.max(0, remaining % 60)).padStart(2, "0");
  const state = STATE_LABEL[p.state] ?? "Unknown";

  const kpiLo = Number(formatUnits(p.kpiLo, 18));
  const kpiHi = Number(formatUnits(p.kpiHi, 18));
  const passKpi = passPrice !== null ? kpiLo + passPrice * (kpiHi - kpiLo) : null;
  const failKpi = failPrice !== null ? kpiLo + failPrice * (kpiHi - kpiLo) : null;

  return (
    <div className="p-5 border border-neutral-800 rounded-lg bg-neutral-950 space-y-3">
      <div className="flex justify-between items-center">
        <div className="font-mono text-lg">Proposal #{p.id.toString()}</div>
        <div className="text-xs uppercase tracking-wide px-2 py-1 rounded bg-neutral-800">{state}</div>
      </div>
      <div className="text-sm text-neutral-400">
        proposer <span className="font-mono">{short(p.proposer)}</span>
      </div>
      <div className="grid grid-cols-2 gap-4 pt-2">
        <BranchCell label="IF PASS" price={passPrice} kpi={passKpi} highlight={passPrice !== null && failPrice !== null && passPrice > failPrice} />
        <BranchCell label="IF FAIL" price={failPrice} kpi={failKpi} highlight={passPrice !== null && failPrice !== null && failPrice > passPrice} />
      </div>
      {state === "Trading" && (
        <div className="text-center text-2xl font-mono pt-2">
          {remaining > 0 ? (
            <>
              decide in <span className="text-emerald-400">{mm}:{ss}</span>
            </>
          ) : (
            <span className="text-amber-400">ready to decide</span>
          )}
        </div>
      )}
      {state === "DecidedPass" && <div className="text-center text-emerald-400 text-lg">PASS queued in timelock</div>}
      {state === "DecidedFail" && <div className="text-center text-neutral-400 text-lg">FAIL — no execution</div>}
      {state === "Resolved" && <div className="text-center text-sky-400 text-lg">Resolved</div>}
    </div>
  );
}

function BranchCell({
  label,
  price,
  kpi,
  highlight,
}: {
  label: string;
  price: number | null;
  kpi: number | null;
  highlight: boolean;
}) {
  return (
    <div className={`p-3 rounded ${highlight ? "bg-emerald-900/30 border border-emerald-800" : "bg-neutral-900"}`}>
      <div className="text-xs text-neutral-400 mb-1">{label}</div>
      <div className="font-mono text-xl">{price === null ? "—" : price.toFixed(4)}</div>
      <div className="text-xs text-neutral-500 mt-1">
        E[KPI] = {kpi === null ? "—" : `${kpi.toFixed(2)} ETH`}
      </div>
    </div>
  );
}

function short(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
