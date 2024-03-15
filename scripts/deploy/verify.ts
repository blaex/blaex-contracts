import { ethers, network, run } from "hardhat";
import {
  LIQUIDITY_VAULT_ADDRESS,
  PERPS_VAULT_ADDRESS,
  PERPS_MARKET_ADDRESS,
} from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  // await run("verify:verify", {
  //   address: LIQUIDITY_VAULT_ADDRESS,
  //   constructorArguments: [wallet.address, wallet.address],
  // });

  // await run("verify:verify", {
  //   address: PERPS_VAULT_ADDRESS,
  //   constructorArguments: [wallet.address, wallet.address],
  // });

  await run("verify:verify", {
    address: PERPS_MARKET_ADDRESS,
    constructorArguments: [
      wallet.address,
      PERPS_VAULT_ADDRESS,
      "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729", // pyth
    ],
  });
}

main();
