import { ethers, network } from "hardhat";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { CONFIG } from "../../utils/constants";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();

  const PerpsMarketContract = new ethers.Contract(
    CONFIG.PERPS_MARKET,
    PERPS_MARKET_ABI,
    wallet1 as any
  );

  const ethPriceFeedId =
    "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";

  const tx = await PerpsMarketContract.createMarket({
    id: 1,
    symbol: "ETH",
    priceFeedId: ethPriceFeedId,
    // maxSkew: ethers.utils.parseEther("1000"),
    maxSkew: 1,
  });
  console.log("tx", tx);
}

main();
