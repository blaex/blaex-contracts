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

  const amount = ethers.utils.parseEther("150");

  // {
  //   "internalType": "uint256",
  //   "name": "market",
  //   "type": "uint256"
  // },
  // {
  //   "internalType": "address",
  //   "name": "collateralToken",
  //   "type": "address"
  // },
  // {
  //   "internalType": "uint256",
  //   "name": "sizeDeltaUsd",
  //   "type": "uint256"
  // },
  // {
  //   "internalType": "uint256",
  //   "name": "collateralDeltaUsd",
  //   "type": "uint256"
  // },
  // {
  //   "internalType": "uint256",
  //   "name": "triggerPrice",
  //   "type": "uint256"
  // },
  // {
  //   "internalType": "uint256",
  //   "name": "acceptablePrice",
  //   "type": "uint256"
  // },
  // {
  //   "internalType": "enum IPerpsMarket.OrderType",
  //   "name": "orderType",
  //   "type": "uint8"
  // },
  // {
  //   "internalType": "bool",
  //   "name": "isLong",
  //   "type": "bool"
  // }

  // enum OrderType {
  //   MarketIncrease,
  //   LimitIncrease,
  //   MarketDecrease,
  //   LimitDecrease,
  //   Liquidation,
  // }

  // const approvedTx = await USDBContract.approve(
  //   PerpsMarketContract.address,
  //   ethers.utils.parseEther("1000")
  // );
  // console.log("approvedTx", approvedTx);
  // await delay(3000);

  const price = await PerpsMarketContract.indexPrice(1);
  const tx = await PerpsMarketContract.createOrder({
    market: 1,
    sizeDeltaUsd: amount.mul(20),
    collateralDeltaUsd: amount,
    triggerPrice: 0,
    acceptablePrice: calculateAcceptablePrice(price, true),
    isLong: true,
    isIncrease: false,
  });
  console.log("tx", tx);
}

main();
