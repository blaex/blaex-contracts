import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { BlaexNetworkConfig } from "../../utils/types/config";
import delay from "../../utils/delay";
import { CONFIG } from "../../utils/constants";
require("dotenv").config();

async function main() {
  const amount = ethers.utils.parseEther("2000");
  const [, wallet] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet as any);

  console.log("LIQUIDITY_VAULT_ADDRESS", CONFIG.LIQUIDITY_VAULT);
  console.log("USDB", USDB);
  const LiquidityVaultContract = new ethers.Contract(
    CONFIG.LIQUIDITY_VAULT,
    LIQUIDITY_VAULT_ABI,
    wallet as any
  );

  const approvedTx = await USDBContract.approve(CONFIG.LIQUIDITY_VAULT, amount);
  console.log("approvedTx", approvedTx);
  await delay(3000);
  const tx = await LiquidityVaultContract.deposit(amount);
  console.log("tx", tx);
}

main();
