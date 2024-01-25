// npx hardhat create-attestation --onchain <BOOLEAN> --network <NETWORK_NAME>
// npx hardhat create-attestation --onchain true --network sepolia
const { types } = require("hardhat/config");
const fs = require('fs');
const colors = require('colors');
const { SchemaEncoder, EAS } = require("@ethereum-attestation-service/eas-sdk");
const { ethers } = require("ethers");
task("create-attestation", "Creates an attestation")
    .addParam("onchain", "To check if the attestation is onchain or offchain", false, types.boolean)
    .setAction(async (taskArgs) => {
        const { run, network } = require('hardhat');
        const networkName = network.name;

        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];

        const EASContractAddress = process.env.EAS_ADDRESS_SEPOLIA;
        const eas = new EAS(EASContractAddress);
        eas.connect(signer);

        console.log(colors.bold("\n==> Running register-schema task..."));

        // hardcoded schema items and values
        const schemaItems = [
            {
                name: "citationUID", value: [
                    ethers.encodeBytes32String("exampleUID1"),
                    ethers.encodeBytes32String("exampleUID2")
                ], type: "bytes32[]"
            },
            { name: "contributorName", value: "Bob", type: "string" },
            { name: "articleTitle", value: 'Why GM is new hello?', type: "string" },
            { name: "articleHash", value: ethers.encodeBytes32String('random hash'), type: "bytes32" },
            { name: "urlOfContent", value: "https://olas.info/1332", type: "string" }
        ];
        // schema details
        const resolver = "0x0000000000000000000000000000000000000000";
        const revocable = false;
        const expirationTime = 0;
        const recipient = "0xe13EE316998654BC47f61d4787f34cE0B50ED7fD";

        // get the schema string from the schema items
        const schema = schemaItems.map(param => `${param.type} ${param.name}`).join(", ");
        // compute schema UID
        const schemaUID = await run("compute-uid", { schema, resolver, revocable });

        console.log(colors.blue("\nTrying to fetch schema:", schemaUID));
        // check if schema exists with the given schema values
        const fetchedSchema = await run("fetch-schema", { uid: schemaUID });
        if (fetchedSchema === null) {
            console.log(colors.red("\nSchema does not exist, exiting..."));
            return;
        }
        // encode schema items
        const schemaEncoder = new SchemaEncoder(schema);
        const encodedSchemaItems = schemaEncoder.encodeData(schemaItems);

        if (taskArgs.onchain) {
            console.log(colors.blue("\nCreating onchain attestation..."));
            try {
                const tx = await eas.attest({
                    schema: schemaUID,
                    data: {
                        recipient,
                        expirationTime,
                        revocable,
                        data: encodedSchemaItems,
                    },
                });

                const attestationUID = await tx.wait();
                // Append attestation UID to the file
                appendObjectToJsonFile(`${networkName}-attestations.json`, attestationUID);

                console.log(colors.green("\nOnchain Attestation successfully created!"));
                console.log(colors.yellow("\nAttestation UID:", attestationUID));
            } catch (error) {
                console.error(colors.red("\nError creating attestation:", error));
            }
        } else {
            const offchain = await eas.getOffchain();
            console.log(colors.blue("\nCreating offchain attestation..."));

            const offchainAttestation = await offchain.signOffchainAttestation({
                recipient,
                // Unix timestamp of when attestation expires. (0 for no expiration)
                expirationTime,
                // Unix timestamp of current time
                time: Math.floor(Date.now() / 1000),
                revocable,
                version: 1,
                nonce: 0,
                schema: schemaUID,
                refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
                data: encodedSchemaItems,
            }, signer);

            // Append offchain attestation object to the file
            appendObjectToJsonFile('offchain-attestations.json', offchainAttestation);

            console.log(colors.green("\nOffchain Attestation successfully created!"));
            console.log(colors.yellow("\nSigned offchain attestation object:", offchainAttestation));
        }

    });

// Function to append an object to a JSON file
const appendObjectToJsonFile = (fileName, object) => {
    let json = [];

    // Check if the file exists and is not empty
    if (fs.existsSync(fileName) && fs.statSync(fileName).size > 0) {
        const data = fs.readFileSync(fileName, 'utf8');
        try {
            json = JSON.parse(data);
        } catch (parseErr) {
            console.error('Error parsing JSON:', parseErr);
            return;
        }
    }

    json.push(object);

    // Convert the array to a JSON string
    // The replacer function is used to convert BigInt to string
    const stringifiedData = JSON.stringify(json, replacer, 2);

    // Write the JSON string to the file
    fs.writeFileSync(fileName, stringifiedData, (err) => {
        if (err) {
            console.error('An error occurred:', err);
            return;
        }
    });
};

// Replacer function to convert BigInt to string
function replacer(key, value) {
    if (typeof value === 'bigint') {
        return value.toString();
    } else {
        return value;
    }
}
