import { ethers, network, run } from "hardhat";
import { abi as factoryAbi } from "../../artifacts/contracts/Factory.sol/Factory.json";
import { BlaexNetworkConfig } from "../../utils/types/config";

async function main() {
  const [wallet] = await ethers.getSigners();

  const USDB = (network.config as BlaexNetworkConfig).USDB;

  const BLI = await ethers.getContractFactory("BLI");
  const BLIContract = await BLI.deploy(wallet.address, wallet.address, USDB);
  await BLIContract.deployed();
  console.log("BLI deployed to:", BLIContract.address);
}

main();
