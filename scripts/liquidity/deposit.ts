import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { abi as BLI_ABI } from "../../artifacts/contracts/BLI.sol/BLI.json";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { BLI_ADDRESS } from "../../utils/constants";
import delay from "../../utils/delay";
require("dotenv").config();

async function main() {
  const amount = ethers.utils.parseEther("1000");
  const [wallet1] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet1 as any);
  const BLIContract = new ethers.Contract(BLI_ADDRESS, BLI_ABI, wallet1 as any);

  const approvedTx = await USDBContract.approve(BLI_ADDRESS, amount);
  console.log("approvedTx", approvedTx);
  await delay(3000);
  const tx = await BLIContract.deposit(amount);
  console.log("tx", tx);
}

main();
