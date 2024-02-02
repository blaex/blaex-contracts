import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { LIQUIDITY_VAULT_ADDRESS } from "../../utils/constants";
import delay from "../../utils/delay";
require("dotenv").config();

async function main() {
  const amount = ethers.utils.parseEther("2000");
  const [, wallet] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet as any);

  console.log("LIQUIDITY_VAULT_ADDRESS", LIQUIDITY_VAULT_ADDRESS);
  console.log("USDB", USDB);
  const LiquidityVaultContract = new ethers.Contract(
    LIQUIDITY_VAULT_ADDRESS,
    LIQUIDITY_VAULT_ABI,
    wallet as any
  );

  const approvedTx = await USDBContract.approve(
    LIQUIDITY_VAULT_ADDRESS,
    amount
  );
  console.log("approvedTx", approvedTx);
  await delay(3000);
  const tx = await LiquidityVaultContract.deposit(amount);
  console.log("tx", tx);
}

main();
