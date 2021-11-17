require("dotenv").config();
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");
require("solidity-coverage");
require('@openzeppelin/hardhat-upgrades');

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY || "";
const KOVAN_PRIVATE_KEY = process.env.KOVAN_PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
	const accounts = await ethers.getSigners();

	for (const account of accounts) {
		console.log(account.address);
	}
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
	solidity: {
		compilers: [
		  	{
				version: "0.5.16",
				settings: {
					optimizer: {
						enabled: true,
						runs: 200
					}
				}
			},
			{
				version: "0.6.0",
				settings: {
					optimizer: {
						enabled: true,
						runs: 200
					}
				}
			},
			{
				version: "0.6.12",
				settings: {
					optimizer: {
						enabled: true,
						runs: 200
					}
				}
			}
		]
	},
	defaultNetwork: "hardhat",
	networks: {
		hardhat: {
		},    
		kovan: {
			url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
			accounts: [`${KOVAN_PRIVATE_KEY}`]
		},
		ganache: {
			url: "http://127.0.0.1:8545",
			gasLimit: 6000000000,
			defaultBalanceEther: 10
		}
  	},
	gasReporter: {
    enabled: false,
    currency: "USD",
  	},
	etherscan: {
		// Your API key for Etherscan
		// Obtain one at https://etherscan.io/
		apiKey: ETHERSCAN_API_KEY
	}
}