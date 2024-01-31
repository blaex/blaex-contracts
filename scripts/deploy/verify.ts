import { ethers, network, run } from "hardhat";
import {
  LIQUIDITY_VAULT_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  await run("verify:verify", {
    address: LIQUIDITY_VAULT_ADDRESS,
    constructorArguments: [wallet.address, wallet.address],
  });

  await run("verify:verify", {
    address: PERPS_VAULT_ADDRESS,
    constructorArguments: [wallet.address],
  });
}

main();
