import { PERPS_MARKET_ADDRESS } from "./../../utils/constants";
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

  const ethPriceFeedId =
    "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";

  // const approvedTx = await USDBContract.approve(
  //   PerpsMarketContract.address,
  //   amount
  // );
  // console.log("approvedTx", approvedTx);
  // await delay(3000);
  // const tx = await PerpsMarketContract.depositCollateral(
  //   wallet2.address,
  //   amount
  // );
  // console.log("tx", tx);

  // const tx = await PerpsMarketContract.settleTrade(
  //   wallet2.address,
  //   amount.div(3).mul(-1),
  //   amount.div(10)
  // );
  // console.log("tx", tx);

  const tx = await PerpsMarketContract.createMarket({
    id: 1,
    symbol: "ETH",
    priceFeedId: ethPriceFeedId,
  });
  console.log("tx", tx);
  delay(3000);
  const price = await PerpsMarketContract.indexPrice(1);
  console.log("price", price.toString());
}

main();
