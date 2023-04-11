require('dotenv').config();
import { HardhatUserConfig } from "hardhat/config";
import '@openzeppelin/hardhat-upgrades';
import "@nomicfoundation/hardhat-toolbox";

const { API_URL, OWNER_PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: "0.8.17",
  networks: {
    hardhat: {
    },
    polygon_mumbai: {
      url: API_URL,
      accounts: [`0x${OWNER_PRIVATE_KEY}`]
    },
    polygon: {
      url: API_URL,
      accounts: [`0x${OWNER_PRIVATE_KEY}`]
    }
  },
  etherscan: {
    apiKey: `${ETHERSCAN_API_KEY}`,
  },
};

export default config;
