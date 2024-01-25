require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("./tasks/register-schema");
require("./tasks/compute-uid");
require("./tasks/fetch-schema");
require("./tasks/create-attestation");
require("./tasks/fetch-attestation");
require('dotenv').config();
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    sepolia: {
      accounts: [process.env.PRIVATE_KEY],
      url: process.env.ETH_NODE_URI_SEPOLIA,
      chainId: 11155111,
    },
  }
};
