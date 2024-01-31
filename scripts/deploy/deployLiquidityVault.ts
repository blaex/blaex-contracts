import { ethers } from "hardhat";

async function main() {
  const [wallet] = await ethers.getSigners();

  const LiquidityVault = await ethers.getContractFactory("LiquidityVault");
  const LiquidityVaultContract = await LiquidityVault.deploy(
    wallet.address,
    wallet.address
  );
  await LiquidityVaultContract.deployed();
  console.log("LiquidityVault deployed to:", LiquidityVaultContract.address);
}

main();
