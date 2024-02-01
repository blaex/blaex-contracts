import { ethers } from "hardhat";
import { PERPS_VAULT_ADDRESS } from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  const PerpsMarket = await ethers.getContractFactory("PerpsMarket");
  const PerpsMarketContract = await PerpsMarket.deploy(
    wallet.address,
    PERPS_VAULT_ADDRESS,
    "0xA2aa501b19aff244D90cc15a4Cf739D2725B5729" // pyth
  );
  await PerpsMarketContract.deployed();
  console.log("PerpsMarket deployed to:", PerpsMarketContract.address);
}

main();
