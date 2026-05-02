import Link from "next/link";
import { FACTORY_ADDRESS } from "@/lib/client";
import { computeLeaderboard } from "@/lib/leaderboard";
import { PERSONAS } from "@/lib/personas";

export const revalidate = 30;

export default async function LeaderboardPage() {
  if (!FACTORY_ADDRESS) {
    return (
      <main className="max-w-3xl mx-auto p-10">
        <p className="text-amber-200">Set NEXT_PUBLIC_FACTORY_ADDRESS first.</p>
      </main>
    );
  }

  const { personas, resolved } = await computeLeaderboard(FACTORY_ADDRESS);
  const ranked = [...personas].sort((a, b) => {
    if (a.avgBrier === null && b.avgBrier === null) return b.fUsdcBalance - a.fUsdcBalance;
    if (a.avgBrier === null) return 1;
    if (b.avgBrier === null) return -1;
    return a.avgBrier - b.avgBrier; // lower Brier = better
  });

  return (
    <main className="max-w-3xl mx-auto p-10 space-y-6">
      <header className="space-y-2">
        <Link href="/" className="text-sm text-neutral-400 hover:text-neutral-200">
          ← back to proposals
        </Link>
        <h1 className="text-3xl font-bold">Persona Leaderboard</h1>
        <p className="text-neutral-400 text-sm">
          Brier score = average (forecast − actual)² across resolved branches. Lower is better. Forecast =
          spot price after the persona's last swap on each branch.
        </p>
      </header>

      <div className="text-xs text-neutral-500">
        {resolved.length} resolved proposal{resolved.length === 1 ? "" : "s"} · scored against actual KPI
      </div>

      <table className="w-full border-separate border-spacing-y-2">
        <thead>
          <tr className="text-left text-xs uppercase text-neutral-500">
            <th className="px-3 py-1">#</th>
            <th className="px-3 py-1">Persona</th>
            <th className="px-3 py-1 text-right">Trades</th>
            <th className="px-3 py-1 text-right">Avg Brier</th>
            <th className="px-3 py-1 text-right">fUSDC</th>
          </tr>
        </thead>
        <tbody>
          {ranked.map((p, i) => {
            const meta = PERSONAS.find((x) => x.id === p.personaId)!;
            return (
              <tr key={p.address} className="bg-neutral-950 border border-neutral-800">
                <td className="px-3 py-3 font-mono">{i + 1}</td>
                <td className="px-3 py-3">
                  <div className="font-medium">{p.label}</div>
                  <div className="text-xs text-neutral-500">{meta.description}</div>
                  <div className="text-xs text-neutral-600 font-mono mt-1">{short(p.address)}</div>
                </td>
                <td className="px-3 py-3 font-mono text-right">{p.trades}</td>
                <td className="px-3 py-3 font-mono text-right">
                  {p.avgBrier === null ? "—" : p.avgBrier.toFixed(4)}
                </td>
                <td className="px-3 py-3 font-mono text-right">{p.fUsdcBalance.toLocaleString()}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {resolved.length === 0 && (
        <div className="p-4 border border-neutral-800 rounded text-neutral-400 text-sm">
          No proposals have resolved yet. Brier scores will populate after the resolver fires on a decided
          proposal. Until then the table ranks by fUSDC bankroll.
        </div>
      )}
    </main>
  );
}

function short(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
