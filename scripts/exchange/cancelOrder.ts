import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { EvmPriceServiceConnection } from "@pythnetwork/pyth-evm-js";
import { CONFIG } from "../../utils/constants";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();

  const PerpsMarketContract = new ethers.Contract(
    CONFIG.PERPS_MARKET,
    PERPS_MARKET_ABI,
    wallet1 as any
  );

  const tx = await PerpsMarketContract.cancelOrder(11);
  console.log("tx", tx);
}

main();
