import { ethers, network } from "hardhat";
import { BlaexNetworkConfig } from "../../utils/types/config";

async function main() {
  const BRIDGE = (network.config as BlaexNetworkConfig).BRIDGE;

  // Wallet setup
  const [wallet1] = await ethers.getSigners();

  // Transaction to send 0.2 Sepolia ETH
  const payload = {
    to: BRIDGE,
    value: ethers.utils.parseEther("0.2"),
  };

  const tx = await wallet1.sendTransaction(payload);
  console.log("tx", tx);
}

main();
