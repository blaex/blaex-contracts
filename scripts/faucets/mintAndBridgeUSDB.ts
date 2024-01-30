import { ethers, network } from "hardhat";
import { abi } from "../../artifacts/contracts/USDB.sol/USDB.json";
import { BlaexNetworkConfig } from "../../utils/types/config";

async function main() {
  const amount = ethers.utils.parseEther("10000");
  const [wallet1] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const BRIDGE = (network.config as BlaexNetworkConfig).BRIDGE;
  const USDBContract = new ethers.Contract(USDB, abi, wallet1 as any);
  // const mintTx = await USDBContract.mint(wallet1.address, amount);
  // console.log(mintTx);
  // const approvedTx = await USDBContract.approve(BRIDGE, amount);
  // console.log("approvedTx", approvedTx);
  const bridgeAbi = [
    "function bridgeERC20(address,address,uint256,uint32,bytes) external",
  ];
  const BridgeContract = new ethers.Contract(BRIDGE, bridgeAbi, wallet1 as any);
  const bridgeTx = await BridgeContract.bridgeERC20(
    "0x7f11f79DEA8CE904ed0249a23930f2e59b43a385",
    "0x4200000000000000000000000000000000000022",
    amount,
    5000000,
    0
  );
  console.log("bridgeTx", bridgeTx);
}

main();
