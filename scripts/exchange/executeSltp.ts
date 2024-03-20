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

  const connection = new EvmPriceServiceConnection(
    "https://hermes.pyth.network"
  ); // See Hermes endpoints section below for other endpoints

  const priceIds = [
    // You can find the ids of prices at https://pyth.network/developers/price-feed-ids#pyth-evm-stable
    // "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43", // BTC/USD price id
    "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace", // ETH/USD price id
  ];

  // In order to use Pyth prices in your protocol you need to submit the price update data to Pyth contract in your target
  // chain. `getPriceFeedsUpdateData` creates the update data which can be submitted to your contract. Then your contract should
  // call the Pyth Contract with this data.
  const priceUpdateData = await connection.getPriceFeedsUpdateData(priceIds);

  const tx = await PerpsMarketContract.executeSltp(1, priceUpdateData, {
    value: 1,
  });
  console.log("tx", tx);
}

main();
