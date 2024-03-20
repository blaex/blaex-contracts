import { network } from "hardhat";
import { BlaexNetworkConfig } from "./types/config";

export const CONFIG = network.config as BlaexNetworkConfig;
