import Anthropic from "@anthropic-ai/sdk";
import type { Persona } from "./personas";

export interface ProposalContext {
  proposalId: bigint;
  txSummary: string; // human-readable description of what executes
  kpiDescription: string; // what the KPI is (e.g. "DAO treasury ETH balance at block N")
  kpiLo: number; // lower bound (same units as KPI)
  kpiHi: number; // upper bound
  currentPassPrice: number; // normalized [0,1]
  currentFailPrice: number; // normalized [0,1]
  treasuryBalanceNow: number; // the current KPI value (helpful prior)
}

export interface Forecast {
  eKpiPass: number; // expected KPI value if proposal passes (raw units)
  eKpiFail: number; // expected KPI value if proposal fails (raw units)
  confidence: number; // [0,1]
  reasoning: string; // one or two sentences
}

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

const MODEL = "claude-sonnet-4-6";

export async function forecast(persona: Persona, ctx: ProposalContext): Promise<Forecast> {
  const userPrompt = `Proposal #${ctx.proposalId}

What executes if passed: ${ctx.txSummary}
KPI: ${ctx.kpiDescription}
KPI bounds: [${ctx.kpiLo}, ${ctx.kpiHi}]
Current KPI value: ${ctx.treasuryBalanceNow}

Market-implied prices (normalized 0..1, where 1 = KPI hits upper bound):
  pass branch: ${ctx.currentPassPrice.toFixed(4)}
  fail branch: ${ctx.currentFailPrice.toFixed(4)}

Forecast the expected KPI value in raw units (not normalized) under each branch.
Respond with ONLY a JSON object matching this schema:

{
  "eKpiPass": <number>,
  "eKpiFail": <number>,
  "confidence": <number in [0, 1]>,
  "reasoning": "<one or two sentences>"
}`;

  const msg = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 400,
    system: persona.systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const text = msg.content
    .map((c) => (c.type === "text" ? c.text : ""))
    .join("")
    .trim();

  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error(`no JSON in reply: ${text}`);
  const parsed = JSON.parse(match[0]);

  return {
    eKpiPass: Number(parsed.eKpiPass),
    eKpiFail: Number(parsed.eKpiFail),
    confidence: Math.max(0, Math.min(1, Number(parsed.confidence))),
    reasoning: String(parsed.reasoning ?? ""),
  };
}
