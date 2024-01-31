// npx hardhat compute-uid --schema <SCHEMA_TEXT> 
const { types } = require("hardhat/config");

task("compute-uid", "Computes the UID for a given schema")
    .addParam("schema", "The schema string")
    .addOptionalParam("resolverAddress", "The resolver address", "0x0000000000000000000000000000000000000000", types.string)
    .addOptionalParam("revocable", "Revocable boolean", false, types.boolean)
    .setAction(async (taskArgs, hre) => {
        const { ethers } = require("ethers");
        const colors = require('colors');
        const isValidAddress = ethers.isAddress(taskArgs.resolverAddress);
        if (!isValidAddress) {
            console.error('Invalid resolver address.');
        }

        const computeUID = () => {
            const encoded = ethers.solidityPacked(
                ["string", "address", "bool"],
                [taskArgs.schema, taskArgs.resolverAddress, taskArgs.revocable]
            );
            return ethers.keccak256(encoded);
        };

        const uid = computeUID();
        console.log(colors.yellow("\nComputed Uid:", uid));
        return uid;
    });