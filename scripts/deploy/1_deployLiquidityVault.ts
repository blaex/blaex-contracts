import { ethers, run } from "hardhat";
import { CONFIG } from "../../utils/constants";
import delay from "../../utils/delay";

async function main() {
  const [wallet] = await ethers.getSigners();

  const LiquidityVault = await ethers.getContractFactory("LiquidityVault");
  const LiquidityVaultContract = await LiquidityVault.deploy(
    CONFIG.USDB,
    CONFIG.BLAST_POINTS,
    wallet.address,
    wallet.address
  );
  await LiquidityVaultContract.deployed();
  console.log("LiquidityVault deployed to:", LiquidityVaultContract.address);

  await delay(3000);
  await run("verify:verify", {
    address: LiquidityVaultContract.address,
    constructorArguments: [
      CONFIG.USDB,
      CONFIG.BLAST_POINTS,
      wallet.address,
      wallet.address,
    ],
  });
}

main();
