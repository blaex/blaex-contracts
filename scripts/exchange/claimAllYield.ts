import {
  PERPS_MARKET_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../../utils/constants";
import { ethers, network } from "hardhat";
import { abi as PERPS_VAULT_ABI } from "../../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import delay from "../../utils/delay";
require("dotenv").config();

async function main() {
  const [wallet1, wallet2] = await ethers.getSigners();

  const PerpsVaultContract = new ethers.Contract(
    PERPS_VAULT_ADDRESS,
    PERPS_VAULT_ABI,
    wallet1 as any
  );

  const tx = await PerpsVaultContract.claimAllYield();
  console.log("tx", tx);
}

main();
