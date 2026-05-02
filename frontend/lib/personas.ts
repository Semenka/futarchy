export interface PersonaMeta {
  id: "bullish" | "bearish" | "contrarian";
  label: string;
  address: `0x${string}`;
  description: string;
}

export const PERSONAS: PersonaMeta[] = [
  {
    id: "bullish",
    label: "Bullish-Claude",
    address: "0xCcb98ae5cd6BeAa40c308AAd4dCf6308f5DdBEEF",
    description: "Tilts pass-branch KPI upward — believes most proposals create value.",
  },
  {
    id: "bearish",
    label: "Bearish-Claude",
    address: "0x1a910206F8620F4C205E51881C3525cd2269c9A5",
    description: "Skeptical prior — assumes treasury spend is value-destructive.",
  },
  {
    id: "contrarian",
    label: "Contrarian-Claude",
    address: "0xCDc04eCA16EFFa1f57DA4e435a4a90d5eA1d02fd",
    description: "Anchors on market price; leans against extremes.",
  },
];
