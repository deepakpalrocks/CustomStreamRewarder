
import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import { privateKeys } from "./utils/wallet"
import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";

const forkingConfig = {
  url: `https://eth-mainnet.g.alchemy.com/v2/3u2LbCrKTp6_DyqsWNc07SKWEqLU0koi`,
};

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
// task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
//   const accounts = await hre.ethers.getSigners();

//   for (const account of accounts) {
//     console.log(account.address);
//   }
// });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.5.16",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
      {
        version: "0.8.15",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
      {
        version: "0.8.19",
        settings: {
          optimizer: { enabled: true, runs: 100 },
        },
      },
    ],
  },
  etherscan: {
    apiKey: process.env.APIKEY,
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: process.env.FORK ? forkingConfig : undefined,
      accounts: getHardhatPrivateKeys(),
      gas: 30193413,
      blockGasLimit: 120000000,
      chainId: 31338,
    },
    devnet:{
      url:"https://rpc.vnet.tenderly.co/devnet/campie/4b3d4d13-c108-4808-83a9-bf7e117e10f5",
      chainId: 42161,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 2000000000000000,
      gas: 15000000,
      blockGasLimit: 702056136595,
      allowUnlimitedContractSize: true,
    },
    mainnet: {
      url: "https://eth-mainnet.g.alchemy.com/v2/3u2LbCrKTp6_DyqsWNc07SKWEqLU0koi",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    arblocalhost: {
      url: "http://127.0.0.1:8549/",
      gas: 80000000,
      timeout: 2000000,
      blockGasLimit: 702056136595,
      gasPrice: 489979591000,
      // accounts: getHardhatPrivateKeys(),
      allowUnlimitedContractSize: true,
    },
  },
};

function getHardhatPrivateKeys() {
  return privateKeys.map((key) => {
    const ONE_MILLION_ETH = "1000000000000000000000000";
    return {
      privateKey: key,
      balance: ONE_MILLION_ETH,
    };
  });
}

export default config;
