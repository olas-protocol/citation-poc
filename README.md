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

## Hardhat
This project uses Hardhat, for helper tasks.

### Running tasks

```shell
npx hardhat <task-name>
```