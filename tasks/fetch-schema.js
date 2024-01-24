// npx hardhat fetch-schema --uid <SCHEMA_UID> --network <NETWORK_NAME>
task("fetch-schema", "Fetches a schema")
    .addParam("uid", "The schema uid")
    .setAction(async (taskArgs, hre) => {
        const { SchemaRegistry } = require("@ethereum-attestation-service/eas-sdk");
        const colors = require('colors');
        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];
        console.log(colors.bold("\n==> Running fetch-schema task..."));

        const schemaRegistryContractAddress = process.env.SCHEMA_REGISTRY_ADDRESS_SEPOLIA;
        const schemaRegistry = new SchemaRegistry(schemaRegistryContractAddress);
        schemaRegistry.connect(signer);
        let schema;
        try {
            schema = await schemaRegistry.getSchema({ uid: taskArgs.uid });
            console.log(colors.green("\nSchema fetched successfully: ", schema));
        } catch (error) {
            console.error(colors.red('\n', error));
        }
        return schema;
    });