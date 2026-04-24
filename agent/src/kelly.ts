/**
 * Kelly sizing for a binary-ish bet on a scalar market.
 *
 * The LONG outcome token pays `kpiNormalized` per unit collateral (kpiNormalized
 * in [0, 1]). Current market price `p` ≈ market-implied E[kpiNormalized].
 *
 * If the trader believes the true expected payout is `eKpi` (also in [0, 1])
 * and p < eKpi, they should BUY long. The edge per unit collateral spent is
 *    edge = eKpi / p - 1      (expected multiple minus 1)
 * Kelly fraction of bankroll, for a simple asset:
 *    f* = edge / (varOfReturn)
 *
 * We approximate varOfReturn by a fixed pessimism factor so agents stay tame.
 * For a hackathon MVP we also fraction Kelly (half-Kelly) to avoid blowup.
 */
export interface KellySignal {
  direction: "long" | "short" | "none";
  fraction: number; // 0..1 — fraction of bankroll to commit this round
}

const HALF_KELLY = 0.5;
const PESSIMISM = 4; // variance proxy

export function kellySize(
  eKpi: number, // belief in [0,1]
  marketPrice: number, // price in [0,1]
  confidence: number, // agent's self-reported confidence in [0,1]
): KellySignal {
  if (marketPrice <= 0 || marketPrice >= 1) return { direction: "none", fraction: 0 };
  if (eKpi <= 0 || eKpi >= 1) return { direction: "none", fraction: 0 };

  if (eKpi > marketPrice + 0.02) {
    const edge = eKpi / marketPrice - 1;
    const f = Math.max(0, Math.min(0.25, (edge / PESSIMISM) * HALF_KELLY * confidence));
    return { direction: "long", fraction: f };
  }
  if (eKpi < marketPrice - 0.02) {
    const edge = (1 - eKpi) / (1 - marketPrice) - 1;
    const f = Math.max(0, Math.min(0.25, (edge / PESSIMISM) * HALF_KELLY * confidence));
    return { direction: "short", fraction: f };
  }
  return { direction: "none", fraction: 0 };
}
