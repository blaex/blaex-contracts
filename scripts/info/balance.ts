import { ethers, network } from "hardhat";
import { abi } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { BlaexNetworkConfig } from "../../utils/types/config";
require("dotenv").config();

async function main() {
  const [wallet1] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, abi, wallet1 as any);

  const ethBalance = await ethers.provider.getBalance(wallet1.address);
  console.log(`Balance on Blast: ${ethers.utils.formatEther(ethBalance)} ETH`);

  const usdbBalance = await USDBContract.balanceOf(wallet1.address);
  console.log(
    `Balance on Blast: ${ethers.utils.formatEther(usdbBalance)} USDB`
  );
}

main();
