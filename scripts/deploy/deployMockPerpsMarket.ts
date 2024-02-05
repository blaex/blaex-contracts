import { ethers } from "hardhat";
import { PERPS_VAULT_ADDRESS } from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  const PerpsMarket = await ethers.getContractFactory("MockPerpsMarket");
  const PerpsMarketContract = await PerpsMarket.deploy(PERPS_VAULT_ADDRESS);
  await PerpsMarketContract.deployed();
  console.log("PerpsMarket deployed to:", PerpsMarketContract.address);
}

main();
