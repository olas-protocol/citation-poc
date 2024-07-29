// npx hardhat create-attestation --schema-uid <SCHEMA-UID> --network <NETWORK_NAME>
// npx hardhat create-attestation --schema-uid  0x0fcfaf1c07cd7f659bfb352c7032d20708707b781cac580fe42eb520a645f35f --onchain true --network sepolia
// NOTE: change data to attest to before running script
const { types, task } = require("hardhat/config");
const fs = require('fs');
const colors = require('colors');
const { SchemaEncoder, EAS } = require("@ethereum-attestation-service/eas-sdk");
const { ethers } = require("ethers");
task("create-attestation", "Creates an attestation")
    .addParam("schemaUid", "Schema which you want to use for attestation")
    .addParam("onchain", "To check if the attestation is onchain or offchain", false, types.boolean)
    .setAction(async (taskArgs) => {
        const { run, network } = require('hardhat');
        const networkName = network.name;

        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];

        const EASContractAddress = process.env.EAS_ADDRESS_SEPOLIA;
        const eas = new EAS(EASContractAddress);
        eas.connect(signer);

        console.log(colors.bold("\n==> Running create-attestation task..."));

        console.log(colors.blue("\nTrying to fetch schema for uid:", taskArgs.schemaUid));
        const fetchedSchema = await run("fetch-schema", { uid: taskArgs.schemaUid });
        if (fetchedSchema === null) {
            console.log(colors.red("\nSchema does not exist, exiting..."));
            return;
        }

        // initialize schemaEncoder with schema string
        const schemaEncoder = new SchemaEncoder(fetchedSchema.schema);
        // NOTE: CHANGE DATA HERE
        // custom attestation data

        // main schema details
        // NOTE: CHANGE DATA HERE
        const recipient = "0xe13EE316998654BC47f61d4787f34cE0B50ED7fD";
        const expirationTime = 0;
        const revocable = false;
        const stakeAmount = ethers.parseEther("0.0001");

        const NEWS_AND_OPINION = ethers.keccak256(ethers.toUtf8Bytes("NewsAndOpinion"));

        const dataToAttest =
            [
                { name: "user", value: signer.address, type: "address" },
                { name: "title", value: 'title', type: "string" },
                { name: "contentUrl", value: 'contentUrl', type: "string" },
                { name: "mediaUrl", value: ethers.encodeBytes32String('mediaUrl'), type: "bytes32" },
                { name: "stakeAmount", value: stakeAmount, type: "uint256" },
                { name: "royaltyAmount", value: 0n, type: "uint256" },
                { name: "typeOfMarket", value: NEWS_AND_OPINION, type: "bytes32" },
                {
                    name: "citationUID", value: [
                        ethers.encodeBytes32String("exampleUID1"),
                        ethers.encodeBytes32String("exampleUID2")
                    ], type: "bytes32[]"
                }
            ]
        // dataToAttest format should match with the schema UID's schema, otherwise encoding will fail
        const encodedData = schemaEncoder.encodeData(dataToAttest);

        if (taskArgs.onchain) {
            console.log(colors.blue("\nCreating onchain attestation..."));
            try {
                const tx = await eas.attest({
                    schema: taskArgs.schemaUid,
                    data: {
                        recipient,
                        expirationTime,
                        revocable,
                        data: encodedData,
                        value: stakeAmount,
                    },
                });

                const attestationUID = await tx.wait();
                // Append attestation UID to the file
                appendObjectToJsonFile(`${networkName}-attestations.json`, 'schemaUID: ' + taskArgs.schemaUid + ' attestationUID: ' + attestationUID);

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
                schema: taskArgs.schemaUid,
                refUID: '0x0000000000000000000000000000000000000000000000000000000000000000',
                data: encodedData,
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
