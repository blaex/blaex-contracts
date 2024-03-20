import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { calculateAcceptablePrice } from "../../utils/trades";
import { CONFIG } from "../../utils/constants";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet1 as any);

  const PerpsMarketContract = new ethers.Contract(
    CONFIG.PERPS_MARKET,
    PERPS_MARKET_ABI,
    wallet1 as any
  );

  const price = await PerpsMarketContract.indexPrice(1);
  const tx = await PerpsMarketContract.updateSltp(
    1,
    price.sub(1),
    price.add(1)
  );
  console.log("tx", tx);
}

main();
