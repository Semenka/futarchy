export const proposalFactoryAbi = [
  {
    type: "event",
    name: "ProposalCreated",
    inputs: [
      { name: "proposalId", type: "uint256", indexed: true },
      { name: "proposer", type: "address", indexed: true },
      { name: "passConditionId", type: "bytes32", indexed: false },
      { name: "failConditionId", type: "bytes32", indexed: false },
      { name: "passAMM", type: "address", indexed: false },
      { name: "failAMM", type: "address", indexed: false },
      { name: "tradingDeadline", type: "uint256", indexed: false },
      { name: "kpiObservationBlock", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ProposalDecided",
    inputs: [
      { name: "proposalId", type: "uint256", indexed: true },
      { name: "outcome", type: "uint8", indexed: false },
      { name: "passPrice", type: "uint256", indexed: false },
      { name: "failPrice", type: "uint256", indexed: false },
    ],
  },
  {
    type: "function",
    name: "nextProposalId",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "getProposal",
    stateMutability: "view",
    inputs: [{ name: "proposalId", type: "uint256" }],
    outputs: [
      { name: "proposer", type: "address" },
      { name: "passAMM", type: "address" },
      { name: "failAMM", type: "address" },
      { name: "passConditionId", type: "bytes32" },
      { name: "failConditionId", type: "bytes32" },
      { name: "tradingDeadline", type: "uint256" },
      { name: "kpiObservationBlock", type: "uint256" },
      { name: "kpiLo", type: "uint256" },
      { name: "kpiHi", type: "uint256" },
      { name: "state", type: "uint8" },
    ],
  },
] as const;

export const futarchyAmmAbi = [
  {
    type: "function",
    name: "getLongPrice",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;
