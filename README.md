# citation-poc
This project contains the smart contracts and related scripts for the Proof of Concept (PoC) of the Olas Citation System.

## Project Setup

 Install Project Dependencies:

```shell
nvm use 16.14.0
```

```shell
npm install
```

Install VSCode extensions - JuanBlanco.solidity

Setup VScode to use correct formatting
    - Create `settings.json` inside `.vscode` folder and add following
```
{
    "[solidity]": {
        "editor.formatOnSave": true,
        "editor.defaultFormatter": "JuanBlanco.solidity"
    },
    "[javascript]": {
        "editor.formatOnSave": true,
    },
}
```
## Contract Libraries
This project uses OpenZeppelin Contracts [v5.0.0](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/) - installed as a Foundry submodule dependency.


## Building and Testing with Forge
This project uses Foundry, for building and testing smart contracts. 

### Install Foundry Dependencies

```shell
forge install
```

### Build smart contracts

```shell
forge build
```

### Testing

```shell
forge test
```

## Deploying

Author Stake:
```shell
forge create src/AuthorStake.sol:AuthorStake --rpc-url <rpc-url> --private-key <pkey>  --etherscan-api-key <api> --verify
```
Royalty Resolver:
```shell
forge create src/RoyaltyResolver.sol:RoyaltyResolver --constructor-args <eas-address> <author-stake-address> --rpc-url <rpc-url> --private-key <private-key> --etherscan-api-key <etherscan-api-key> --verify
```

Olas Hub:
```shell
forge create src/OlasHub.sol:OlasHub --constructor-args <eas-address> <schema-uid> --rpc-url <rpc-url> --private-key <private-key> --etherscan-api-key <etherscan-api-key> --verify
```

## Verifications
If Foundry fails to verify the contracts during deployment, they can be verified with the following command:

```shell
forge verify-contract <contract-address> <contract-location> --constructor-args $(cast abi-encode "constructor(<arg1-name>,<arg2-name>)" <arg1-value> <arg2-value>) --rpc-url <rpc-url> --etherscan-api-key <etherscan-api-key> --watch

```

## Deployed Contracts
Here are the addresses of the deployed contracts along with their Etherscan links:

- **Author Stake:** [0x02F4AC89cBeEa72804a6F2c698F642f156D82E7E](https://sepolia.etherscan.io/address/0x02F4AC89cBeEa72804a6F2c698F642f156D82E7E)
- **Royalty Resolver:** [0xe201527cAd12e2a6869A3eEd83415B9eCBDd0AC5](https://sepolia.etherscan.io/address/0xe201527cAd12e2a6869A3eEd83415B9eCBDd0AC5)
- **Olas Hub:** [0x079725B2D866bC50dE82ff03Ef5502Fc3C5EF349](https://sepolia.etherscan.io/address/0x079725B2D866bC50dE82ff03Ef5502Fc3C5EF349)


## Hardhat
This project uses Hardhat, for helper tasks.

### Running tasks

```shell
npx hardhat <task-name>
```