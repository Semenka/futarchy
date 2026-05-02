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
  {
    type: "event",
    name: "Swap",
    inputs: [
      { name: "sender", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "collateralIn", type: "uint256", indexed: false },
      { name: "longIn", type: "uint256", indexed: false },
      { name: "collateralOut", type: "uint256", indexed: false },
      { name: "longOut", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Sync",
    inputs: [
      { name: "reserveCollateral", type: "uint112", indexed: false },
      { name: "reserveLong", type: "uint112", indexed: false },
    ],
  },
] as const;

export const erc20Abi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

export const bctAbi = [
  {
    type: "function",
    name: "conditions",
    stateMutability: "view",
    inputs: [{ name: "conditionId", type: "bytes32" }],
    outputs: [
      { name: "oracle", type: "address" },
      { name: "questionId", type: "bytes32" },
      { name: "resolved", type: "bool" },
      { name: "numerator0", type: "uint128" },
      { name: "numerator1", type: "uint128" },
      { name: "denominator", type: "uint128" },
    ],
  },
] as const;
