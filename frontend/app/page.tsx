import { client, FACTORY_ADDRESS } from "@/lib/client";
import { proposalFactoryAbi } from "@/lib/abi";
import { ProposalCard } from "@/components/ProposalCard";

export const revalidate = 5;

export default async function HomePage() {
  if (!FACTORY_ADDRESS) {
    return (
      <main className="max-w-3xl mx-auto p-10 space-y-6">
        <Header />
        <div className="p-5 border border-amber-800 rounded bg-amber-900/20 text-amber-200">
          <p className="font-semibold mb-1">Configuration required</p>
          <p className="text-sm">
            Set <code className="font-mono">NEXT_PUBLIC_FACTORY_ADDRESS</code> in
            <code className="font-mono"> frontend/.env.local</code>. Deploy the contracts with{" "}
            <code className="font-mono">forge script script/Deploy.s.sol --broadcast</code> first.
          </p>
        </div>
      </main>
    );
  }

  const factory = FACTORY_ADDRESS;
  const next = (await client.readContract({
    address: factory,
    abi: proposalFactoryAbi,
    functionName: "nextProposalId",
  })) as bigint;

  const ids = [];
  for (let i = next - 1n; i >= 0n && ids.length < 10; i--) ids.push(i);

  return (
    <main className="max-w-3xl mx-auto p-10 space-y-6">
      <Header />
      {ids.length === 0 ? (
        <p className="text-neutral-400">No proposals yet.</p>
      ) : (
        <div className="space-y-4">
          {ids.map((id) => (
            <ProposalCard key={id.toString()} factory={factory} id={id} />
          ))}
        </div>
      )}
    </main>
  );
}

function Header() {
  return (
    <header className="space-y-2">
      <h1 className="text-3xl font-bold">Toy DAO · Futarchy</h1>
      <p className="text-neutral-400 text-sm max-w-prose">
        Every proposal spawns two conditional markets (IF-pass / IF-fail) on the DAO's treasury KPI. AI
        agents trade them. Whichever branch prices the KPI higher auto-executes via timelock.
      </p>
    </header>
  );
}
