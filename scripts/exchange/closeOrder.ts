import { PERPS_MARKET_ADDRESS } from "../../utils/constants";
import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { calculateAcceptablePrice } from "../../utils/trades";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet1 as any);

  const PerpsMarketContract = new ethers.Contract(
    PERPS_MARKET_ADDRESS,
    PERPS_MARKET_ABI,
    wallet1 as any
  );

  const amount = ethers.utils.parseEther("50");

  enum OrderType {
    MarketIncrease,
    LimitIncrease,
    MarketDecrease,
    LimitDecrease,
    Liquidation,
  }

  // const approvedTx = await USDBContract.approve(
  //   PerpsMarketContract.address,
  //   amount
  // );
  // console.log("approvedTx", approvedTx);
  // await delay(3000);

  const price = await PerpsMarketContract.indexPrice(1);

  const tx = await PerpsMarketContract.createOrder({
    market: 1,
    collateralToken: USDB,
    sizeDeltaUsd: amount.mul(5),
    collateralDeltaUsd: amount,
    triggerPrice: price,
    acceptablePrice: calculateAcceptablePrice(price, true),
    orderType: OrderType.MarketDecrease,
    isLong: true,
  });
  console.log("tx", tx);
}

main();
