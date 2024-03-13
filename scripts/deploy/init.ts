import { ethers } from "hardhat";
import { abi as LIQUIDITY_VAULT_ABI } from "../../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { abi as PERPS_VAULT_ABI } from "../../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import { abi as PERPS_MARKET_ABI } from "../../artifacts/contracts/exchange/PerpsMarket.sol/PerpsMarket.json";
import {
  LIQUIDITY_VAULT_ADDRESS,
  PERPS_MARKET_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../../utils/constants";
import delay from "../../utils/delay";

async function main() {
  const [wallet1] = await ethers.getSigners();

  console.log("LIQUIDITY_VAULT_ADDRESS", LIQUIDITY_VAULT_ADDRESS);
  console.log("PERPS_VAULT_ADDRESS", PERPS_VAULT_ADDRESS);

  const LiquidityVaultContract = new ethers.Contract(
    LIQUIDITY_VAULT_ADDRESS,
    LIQUIDITY_VAULT_ABI,
    wallet1 as any
  );

  const PerpsVaultContract = new ethers.Contract(
    PERPS_VAULT_ADDRESS,
    PERPS_VAULT_ABI,
    wallet1 as any
  );

  // const PerpsMarketContract = new ethers.Contract(
  //   PERPS_MARKET_ADDRESS,
  //   PERPS_MARKET_ABI,
  //   wallet1 as any
  // );

  const tx1 = await LiquidityVaultContract.setPerpsVault(PERPS_VAULT_ADDRESS);
  console.log("tx1", tx1);

  delay(3000);

  const tx2 = await PerpsVaultContract.setLiquidityVault(
    LIQUIDITY_VAULT_ADDRESS
  );
  console.log("tx2", tx2);

  // delay(3000);

  // const tx3 = await PerpsVaultContract.setPerpsMarket(PERPS_MARKET_ADDRESS);
  // console.log("tx3", tx3);

  // delay(3000);

  // const tx4 = await PerpsMarketContract.setPerpsVault(PERPS_VAULT_ADDRESS);
  // console.log("tx4", tx4);
}

main();
