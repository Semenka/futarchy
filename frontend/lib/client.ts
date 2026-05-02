import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";

const RPC = process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.sepolia.org";

export const client = createPublicClient({
  chain: sepolia,
  transport: http(RPC),
});

export const FACTORY_ADDRESS = process.env.NEXT_PUBLIC_FACTORY_ADDRESS as `0x${string}` | undefined;
