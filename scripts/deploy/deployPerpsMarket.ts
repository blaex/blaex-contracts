import { ethers, run } from "hardhat";
import {
  PERPS_MARKET_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../../utils/constants";
import { abi as PERPS_VAULT_ABI } from "../../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";

async function main() {
  const [wallet] = await ethers.getSigners();

  const PerpsVaultContract = new ethers.Contract(
    PERPS_VAULT_ADDRESS,
    PERPS_VAULT_ABI,
    wallet as any
  );

  // const PerpsMarketContract = new ethers.Contract(
  //   PERPS_MARKET_ADDRESS,
  //   PERPS_MARKET_ABI,
  //   wallet as any
  // );

  const PerpsMarket = await ethers.getContractFactory("PerpsMarket");
  const PerpsMarketContract = await PerpsMarket.deploy(
    wallet.address,
    PERPS_VAULT_ADDRESS,
    "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729" // pyth
  );
  await PerpsMarketContract.deployed();
  console.log("PerpsMarket deployed to:", PerpsMarketContract.address);

  delay(3000);

  const tx = await PerpsVaultContract.setPerpsMarket(
    PerpsMarketContract.address
  );
  console.log("tx", tx);

  delay(3000);

  const marketTx = await PerpsMarketContract.createMarket({
    id: 1,
    symbol: "ETH",
    priceFeedId:
      "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
  });
  console.log("marketTx", marketTx);

  // await run("verify:verify", {
  //   address: PerpsMarketContract.address,
  //   constructorArguments: [
  //     wallet.address,
  //     PERPS_VAULT_ADDRESS,
  //     "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", // pyth
  //   ],
  // });
}

main();
