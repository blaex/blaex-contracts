import { NetworkConfig } from "hardhat/types";

export type BlaexNetworkConfig = NetworkConfig & {
  BRIDGE: string;
  USDB: string;
  url: string;
};
