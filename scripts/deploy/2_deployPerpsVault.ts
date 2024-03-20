import { ethers, run } from "hardhat";
import { CONFIG } from "../../utils/constants";
import delay from "../../utils/delay";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";

async function main() {
  const [wallet, feeReceiver] = await ethers.getSigners();

  const PerpsVault = await ethers.getContractFactory("PerpsVault");
  const PerpsVaultContract = await PerpsVault.deploy(
    CONFIG.LIQUIDITY_VAULT,
    CONFIG.USDB,
    CONFIG.BLAST_POINTS,
    wallet.address,
    wallet.address
  );
  await PerpsVaultContract.deployed();
  console.log("PerpsVault deployed to:", PerpsVaultContract.address);

  await delay(3000);
  await run("verify:verify", {
    address: PerpsVaultContract.address,
    constructorArguments: [
      CONFIG.LIQUIDITY_VAULT,
      CONFIG.USDB,
      CONFIG.BLAST_POINTS,
      wallet.address,
      wallet.address,
    ],
  });

  const LiquidityVaultContract = new ethers.Contract(
    CONFIG.LIQUIDITY_VAULT,
    LIQUIDITY_VAULT_ABI,
    wallet as any
  );

  const tx = await LiquidityVaultContract.setPerpsVault(
    PerpsVaultContract.address
  );
  console.log("setTx", tx);
}

main();
