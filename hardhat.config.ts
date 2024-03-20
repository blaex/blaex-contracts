require("dotenv").config();
import "hardhat-gas-reporter";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
// import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
      viaIR: true,
      metadata: {
        bytecodeHash: "none",
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    sepolia: {
      url: process.env.SEPOLIA_NODE_URL,
      accounts: [
        process.env.PRIVATE_KEY_1!,
        process.env.PRIVATE_KEY_2!,
        process.env.PRIVATE_KEY_3!,
      ],
      ...{
        BRIDGE: "0xc644cc19d2A9388b71dd1dEde07cFFC73237Dca8",
        USDB: "0x7f11f79DEA8CE904ed0249a23930f2e59b43a385",
      },
    },
    testnet: {
      url: process.env.TESTNET_NODE_URL,
      accounts: [
        process.env.PRIVATE_KEY_1!,
        process.env.PRIVATE_KEY_2!,
        process.env.PRIVATE_KEY_3!,
      ],
      ...{
        USDB: "0x4200000000000000000000000000000000000022",
        BLAST_POINTS: "0x2fc95838c71e76ec69ff817983BFf17c710F34E0",
        LIQUIDITY_VAULT: "0x909f03AD2fa1b7b351aB84b161a68F49970A56e4",
        PERPS_VAULT: "0x19d979c24dA579E3fBd5D98c4AeA09901Fa1C7a1",
        PERPS_MARKET: "0x86D262BF5033Af29EAe1F1F071F4Fda43466fcE6",
      },
    },
    mainnet: {
      url: process.env.MAINNET_NODE_URL,
      accounts: [
        process.env.PRIVATE_KEY_1!,
        process.env.PRIVATE_KEY_2!,
        process.env.PRIVATE_KEY_3!,
      ],
      ...{
        USDB: "0x4300000000000000000000000000000000000003",
        BLAST_POINTS: "0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800",
        LIQUIDITY_VAULT: "",
        PERPS_VAULT: "",
        PERPS_MARKET: "",
      },
    },
  },
  gasReporter: {
    currency: "USD",
    token: "ETH",
    gasPrice: 22,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: {
      blast: process.env.BlAST_SCAN_API_KEY!,
      blast_sepolia: "blast_sepolia", // apiKey is not required, just set a placeholder
    },
    customChains: [
      {
        network: "blast_sepolia",
        chainId: 168587773,
        urls: {
          apiURL:
            "https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan",
          browserURL: "https://testnet.blastscan.io",
        },
      },
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.blastscan.io/api",
          browserURL: "https://blastscan.io",
        },
      },
    ],
  },
};

export default config;
