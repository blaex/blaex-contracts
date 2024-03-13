import { PERPS_MARKET_ADDRESS } from "../../utils/constants";
import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { BlaexNetworkConfig } from "../../utils/types/config";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();

  const PerpsMarketContract = new ethers.Contract(
    PERPS_MARKET_ADDRESS,
    PERPS_MARKET_ABI,
    wallet1 as any
  );

  const tx = await PerpsMarketContract.executeOrder(2);
  console.log("tx", tx);
}

main();
