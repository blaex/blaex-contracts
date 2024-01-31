import { ethers, network } from "hardhat";
import { abi as USDB_ABI } from "../artifacts/contracts/USDB.sol/USDB.json";
import { abi as LIQUIDITY_VAULT_ABI } from "../artifacts/contracts/LiquidityVault.sol/LiquidityVault.json";
import { abi as PERPS_VAULT_ABI } from "../artifacts/contracts/PerpsVault.sol/PerpsVault.json";
import { abi as MOCK_PERPS_MARKET_ABI } from "../artifacts/contracts/test/MockPerpsMarket.sol/MockPerpsMarket.json";
import { BlaexNetworkConfig } from "../utils/types/config";
import {
  LIQUIDITY_VAULT_ADDRESS,
  PERPS_VAULT_ADDRESS,
} from "../utils/constants";
import delay from "../utils/delay";
require("dotenv").config();

async function main() {
  const amount = ethers.utils.parseEther("1");
  const [wallet1, wallet2] = await ethers.getSigners();
  const USDB = (network.config as BlaexNetworkConfig).USDB;
  const USDBContract = new ethers.Contract(USDB, USDB_ABI, wallet1 as any);

  console.log("LIQUIDITY_VAULT_ADDRESS", LIQUIDITY_VAULT_ADDRESS);
  console.log("USDB", USDB);
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
  const PerpsMarketContract = new ethers.Contract(
    "0xD4c8b3710d399c1810e48365727FD28bD4ec0314",
    MOCK_PERPS_MARKET_ABI,
    wallet1 as any
  );

  // const approvedTx = await USDBContract.approve(
  //   PerpsMarketContract.address,
  //   amount
  // );
  // console.log("approvedTx", approvedTx);
  // await delay(3000);
  // const tx = await PerpsMarketContract.depositCollateral(
  //   wallet2.address,
  //   amount
  // );
  // console.log("tx", tx);

  // const tx = await PerpsMarketContract.settleTrade(
  //   wallet2.address,
  //   amount.div(3).mul(-1),
  //   amount.div(10)
  // );
  // console.log("tx", tx);

  const balance = await PerpsVaultContract.balanceOf(wallet2.address);

  console.log("balance", balance.toString());

  const tx = await PerpsMarketContract.withdrawCollateral(
    wallet2.address,
    balance
  );
  console.log("tx", tx);
}

main();

966666666666666667;
