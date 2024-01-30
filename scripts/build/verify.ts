import { ethers, network, run } from "hardhat";
import { BlaexNetworkConfig } from "../../utils/types/config";
import { BLI_ADDRESS } from "../../utils/constants";

async function main() {
  const [wallet] = await ethers.getSigners();

  const BLI = { address: BLI_ADDRESS };

  await run("verify:verify", {
    address: BLI.address,
    constructorArguments: [wallet.address, wallet.address],
  });
}

main();
