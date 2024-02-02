import { ethers, network } from "hardhat";
import { abi as MOCK_PERPS_MARKET_ABI } from "../artifacts/contracts/test/MockPerpsMarket.sol/MockPerpsMarket.json";
import { BlaexNetworkConfig } from "../utils/types/config";

import delay from "../utils/delay";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;

  const PerpsMarketContract = new ethers.Contract(
    "0xAE40836Be001c2a8D789B672C6DbE3b0B7beE3C4",
    MOCK_PERPS_MARKET_ABI,
    wallet1 as any
  );

  enum OrderType {
    MarketIncrease,
    LimitIncrease,
    MarketDecrease,
    LimitDecrease,
    Liquidation,
  }

  const price = 2000;
  const leverage = 10;

  const tx1 = await PerpsMarketContract.emitCreateOrder(
    1, // id
    OrderType.MarketIncrease,
    true, // isLong
    wallet2.address,
    1, // ETH
    USDB,
    ethers.utils.parseEther("300"),
    ethers.utils.parseEther("300").mul(leverage).div(price),
    ethers.utils.parseEther(price.toString()),
    ethers.utils.parseEther(price.toString()).mul(102).div(100),
    ethers.utils.parseEther("1")
  );
  console.log("tx1", tx1);
  delay(3000);
  const tx2 = await PerpsMarketContract.emitExecuteOrder(
    1,
    ethers.utils.parseEther(price.toString()).mul(101).div(100),
    Math.round(Date.now() / 1000)
  );
  console.log("tx2", tx2);

  // const tx2 = await PerpsMarketContract.emitCancelOrder(
  //   1,
  // );
  // console.log("tx2", tx2);
}

main();
