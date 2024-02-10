import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-viem";
import "@typechain/hardhat";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "hardhat-tracer";
import { HardhatUserConfig } from "hardhat/config";
import "solidity-coverage";
import "tsconfig-paths/register";
// import "@tenderly/hardhat-tenderly";
// import "hardhat-ethernal";

import * as dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 7777,
      },
    },
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    deploy: "./deploy",
    sources: "./contracts",
    tests: "./tests",
  },
  gasReporter: {
    currency: "USD",
    // gasPrice: 20, // in gwei
    enabled: true,
    coinmarketcap: process.env.COINMARKETCAP_KEY ?? "",
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
  },
  networks: {
    localhost: {
      accounts: {
        mnemonic: "test test test test test test test test test test test test",
      },
      live: false,
      saveDeployments: true,
      tags: ["dev"],
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL as string,
      accounts: [process.env.SEPOLIA_DEPLOYER_KEY as string],
      live: true,
      saveDeployments: true,
      tags: ["uat"],
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL as string,
      accounts: [process.env.MAINNET_DEPLOYER_KEY as string],
      live: true,
      saveDeployments: true,
      tags: ["prod"],
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    alice: {
      default: 1,
    },
    bob: {
      default: 2,
    },
  },
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY as string,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY as string,
  },
};

export default config;
