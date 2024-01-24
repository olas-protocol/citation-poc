
// npx hardhat register-schema --schema <SCHEMA_TEXT> --network<NETWORK_NAME>

const { types, task } = require("hardhat/config");

task("register-schema", "Registers a schema")
    .addParam("schema", "The schema string")
    .addOptionalParam("resolver", "The resolver address", "0x0000000000000000000000000000000000000000", types.string)
    .addOptionalParam("revocable", "Revocable boolean", false, types.boolean)
    .setAction(async (taskArgs, hre) => {
        const { SchemaRegistry } = require("@ethereum-attestation-service/eas-sdk");
        const colors = require('colors');
        const { run, network } = require('hardhat');
        const fs = require('fs');

        console.log(colors.bold("\n==> Running register-schema task..."));

        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];
        console.log(colors.yellow("\nSigner Address:", signer.address));

        const schemaRegistryContractAddress = process.env.SCHEMA_REGISTRY_ADDRESS_SEPOLIA;
        const schemaRegistry = new SchemaRegistry(schemaRegistryContractAddress);
        schemaRegistry.connect(signer);


        const schemaParams = {
            schema: taskArgs.schema,
            resolver: taskArgs.resolver,
            revocable: taskArgs.revocable
        };

        // compute schema UID
        const computedUid = await run("compute-uid", schemaParams);

        // checks if schema exists, if not, registers it
        let existingSchema;
        try {
            existingSchema = await schemaRegistry.getSchema({ uid: computedUid });
            console.log(colors.red('\nSchema already exists:', existingSchema, '\n script exiting'));
        } catch (error) {
            if (error.message === 'Schema not found') {
                existingSchema = null;
            }
        }

        if (existingSchema === null) {
            console.log(colors.blue("\nSchema does not exist, registering..."));
            const transaction = await schemaRegistry.register(schemaParams);
            const schemaUID = await transaction.wait();
            fs.appendFileSync('./' + network.name + '-registered-schema-uids.txt', taskArgs.schema + ' ' + schemaUID + '\n');
            console.log(colors.green("\nSchema successfully registered!"));
        }
    });

