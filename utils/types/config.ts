import { NetworkConfig } from "hardhat/types";

export type BlaexNetworkConfig = NetworkConfig & {
  BRIDGE: string;
  USDB: string;
  BLAST_POINTS: string;
  LIQUIDITY_VAULT: string;
  PERPS_VAULT: string;
  PERPS_MARKET: string;
  url: string;
};
