import { ethers, run } from "hardhat";

import { abi as PERPS_VAULT_ABI } from "../../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import delay from "../../utils/delay";
import { CONFIG } from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  const PerpsVaultContract = new ethers.Contract(
    CONFIG.PERPS_VAULT,
    PERPS_VAULT_ABI,
    wallet as any
  );

  const PerpsMarket = await ethers.getContractFactory("PerpsMarket");
  const PerpsMarketContract = await PerpsMarket.deploy(
    CONFIG.PERPS_VAULT,
    CONFIG.USDB,
    CONFIG.BLAST_POINTS,
    "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", // pyth
    wallet.address
  );
  await PerpsMarketContract.deployed();
  console.log("PerpsMarket deployed to:", PerpsMarketContract.address);

  delay(3000);
  // const PerpsMarketContract = new ethers.Contract(
  //   CONFIG.PERPS_MARKET,
  //   PERPS_MARKET_ABI,
  //   wallet as any
  // );

  const tx = await PerpsVaultContract.setPerpsMarket(
    PerpsMarketContract.address
  );
  console.log("setTx", tx);

  delay(3000);

  await run("verify:verify", {
    address: PerpsMarketContract.address,
    constructorArguments: [
      CONFIG.PERPS_VAULT,
      CONFIG.USDB,
      CONFIG.BLAST_POINTS,
      "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", // pyth
      wallet.address,
    ],
  });

  const marketTx = await PerpsMarketContract.createMarket({
    id: 1,
    symbol: "ETH",
    priceFeedId:
      "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
    maxSkew: 1,
  });
  console.log("marketTx", marketTx);
}

main();
