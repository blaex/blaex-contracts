import { ethers, network } from "hardhat";
import { BlaexNetworkConfig } from "../../utils/types/config";

async function main() {
  const BRIDGE = (network.config as BlaexNetworkConfig).BRIDGE;

  const blastProvider = new ethers.providers.JsonRpcProvider(
    "https://sepolia.blast.io"
  );

  // Wallet setup
  const [wallet1] = await ethers.getSigners();

  // Transaction to send 0.1 Sepolia ETH
  const payload = {
    to: BRIDGE,
    value: ethers.utils.parseEther("0.1"),
  };

  const tx = await wallet1.sendTransaction(payload);
  console.log("tx", tx);
  await tx.wait();

  // Confirm the bridged balance on Blast
  const balance = await blastProvider.getBalance(wallet1.address);
  console.log(`Balance on Blast: ${ethers.utils.formatEther(balance)} ETH`);
}

main();
