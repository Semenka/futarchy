import { GoogleGenerativeAI, SchemaType } from "@google/generative-ai";
import type { Persona } from "./personas";

export interface ProposalContext {
  proposalId: bigint;
  txSummary: string;
  kpiDescription: string;
  kpiLo: number;
  kpiHi: number;
  currentPassPrice: number;
  currentFailPrice: number;
  treasuryBalanceNow: number;
}

export interface Forecast {
  eKpiPass: number;
  eKpiFail: number;
  confidence: number;
  reasoning: string;
}

const MODEL = "gemini-2.5-flash";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY ?? "");

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

  const model = genAI.getGenerativeModel({
    model: MODEL,
    systemInstruction: persona.systemPrompt,
    generationConfig: {
      responseMimeType: "application/json",
      maxOutputTokens: 4096,
      responseSchema: {
        type: SchemaType.OBJECT,
        properties: {
          eKpiPass: { type: SchemaType.NUMBER },
          eKpiFail: { type: SchemaType.NUMBER },
          confidence: { type: SchemaType.NUMBER },
          reasoning: { type: SchemaType.STRING },
        },
        required: ["eKpiPass", "eKpiFail", "confidence", "reasoning"],
      },
    },
  });

  const result = await model.generateContent(userPrompt);
  const text = result.response.text().trim();

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
