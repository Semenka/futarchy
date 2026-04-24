import { createPublicClient, http } from "viem";
import { baseSepolia } from "viem/chains";

const RPC = process.env.NEXT_PUBLIC_RPC_URL ?? "https://sepolia.base.org";

export const client = createPublicClient({
  chain: baseSepolia,
  transport: http(RPC),
});

export const FACTORY_ADDRESS = process.env.NEXT_PUBLIC_FACTORY_ADDRESS as `0x${string}` | undefined;
