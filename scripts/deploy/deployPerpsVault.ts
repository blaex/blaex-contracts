import { ethers } from "hardhat";

async function main() {
  const [wallet, feeReceiver] = await ethers.getSigners();

  const PerpsVault = await ethers.getContractFactory("PerpsVault");
  const PerpsVaultContract = await PerpsVault.deploy(
    wallet.address,
    wallet.address
  );
  await PerpsVaultContract.deployed();
  console.log("PerpsVault deployed to:", PerpsVaultContract.address);
}

main();
