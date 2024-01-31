import { ethers, network } from "hardhat";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { LIQUIDITY_VAULT_ADDRESS } from "../../utils/constants";
require("dotenv").config();

async function main() {
  const amount = ethers.utils.parseEther("1000");
  const [wallet1] = await ethers.getSigners();
  const LiquidityVaultContract = new ethers.Contract(
    LIQUIDITY_VAULT_ADDRESS,
    LIQUIDITY_VAULT_ABI,
    wallet1 as any
  );

  const tx = await LiquidityVaultContract.withdraw(amount);
  console.log("tx", tx);
}

main();
