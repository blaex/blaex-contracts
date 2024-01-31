import { ethers } from "hardhat";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { abi as PERPS_VAULT_ABI } from "../../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import {
  LIQUIDITY_VAULT_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../../utils/constants";
import delay from "../../utils/delay";

async function main() {
  const [wallet1] = await ethers.getSigners();

  const LiquidityVaultContract = new ethers.Contract(
    LIQUIDITY_VAULT_ADDRESS,
    LIQUIDITY_VAULT_ABI,
    wallet1 as any
  );

  const PerpsVaultContract = new ethers.Contract(
    PERPS_VAULT_ADDRESS,
    PERPS_VAULT_ABI,
    wallet1 as any
  );

  // const tx1 = await LiquidityVaultContract.setPerpsVault(PERPS_VAULT_ADDRESS);
  // console.log("tx1", tx1);

  // delay(3000);

  // const tx2 = await PerpsVaultContract.setLiquidityVault(
  //   LIQUIDITY_VAULT_ADDRESS
  // );
  // console.log("tx2", tx2);

  // delay(3000);

  const tx3 = await PerpsVaultContract.setPerpsMarket(
    "0xD4c8b3710d399c1810e48365727FD28bD4ec0314"
  );
  console.log("tx3", tx3);
}

main();
