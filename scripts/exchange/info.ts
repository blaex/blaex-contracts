import { PERPS_MARKET_ADDRESS } from "../../utils/constants";
import { ethers, network } from "hardhat";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();

  const PerpsMarketContract = new ethers.Contract(
    PERPS_MARKET_ADDRESS,
    PERPS_MARKET_ABI,
    wallet1 as any
  );
  const market = await PerpsMarketContract.getMarket(1);
  console.log(
    "market",
    market.map((e: any) => e.toString())
  );

  const openPositions = await PerpsMarketContract.getOpenPositions(
    wallet1.address
  );
  console.log(
    "openPositions",
    openPositions.map((e: any) => e.toString())
  );

  const position1 = await PerpsMarketContract.getPosition(1);
  console.log(
    "position1",
    position1.map((e: any) => e.toString())
  );

  const position2 = await PerpsMarketContract.getPosition(2);
  console.log(
    "position2",
    position2.map((e: any) => e.toString())
  );

  const price = await PerpsMarketContract.indexPrice(1);
  console.log("price", price.toString());
}

main();
