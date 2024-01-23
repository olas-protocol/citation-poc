
// npx hardhat register-schema --schema <SCHEMA_TEXT> --network<NETWORK_NAME>
const { types, task } = require("hardhat/config");

task("register-schema", "Registers a schema")
    .addParam("schema", "The schema string")
    .addOptionalParam("resolver", "The resolver address", "0x0000000000000000000000000000000000000000", types.string)
    .addOptionalParam("revocable", "Revocable boolean", false, types.boolean)
    .setAction(async (taskArgs, hre) => {
        const { SchemaRegistry } = require("@ethereum-attestation-service/eas-sdk");
        const colors = require('colors');
        const { run } = require('hardhat');
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

        // check if schema exists, if not, register it
        try {
            console.log(colors.blue("\nChecking if the schema already exists in the registry..."));
            const existingSchema = await schemaRegistry.getSchema({ uid: computedUid });
            console.error(colors.red('\nSchema already exists:', existingSchema));
            // Exit the task if the schema already exists
            return
        } catch (error) {
            // Proceed if the schema does not exist
            console.log(colors.blue("\nSchema does not exist, registering..."));
            try {
                const transaction = await schemaRegistry.register(schemaParams);
                const schemaUID = await transaction.wait();
                // Write the schema UID to a file
                fs.appendFileSync('./registered-schmea-uids.txt', schemaUID + '\n');
                console.log(colors.green("\nSchema successfully registered!"));
            } catch (error) {
                console.error(colors.red("\nError registering schema:", error));
                console.log(error);
            }
        }
    });

