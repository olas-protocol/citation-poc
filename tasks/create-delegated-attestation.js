// npx hardhat create-attestation --schema-uid <SCHEMA-UID> --network <NETWORK_NAME>
// npx hardhat create-attestation --schema-uid  0x0fcfaf1c07cd7f659bfb352c7032d20708707b781cac580fe42eb520a645f35f  --network sepolia
// NOTE: change data to attest to before running script
const { types, task } = require("hardhat/config");
const fs = require('fs');
const colors = require('colors');
const { SchemaEncoder, EAS, Delegated, ZERO_BYTES32 } = require("@ethereum-attestation-service/eas-sdk");
const { ethers } = require("ethers");
task("create-delegated-attestation", "Creates an attestation")
    .addParam("schemaUid", "Schema which you want to use for attestation")
    .setAction(async (taskArgs) => {
        const { run, network } = require('hardhat');
        const networkName = network.name;
        const chainID = network.config.chainId;
        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];

        console.log(colors.blue("\nNetwork:", networkName));
        console.log(colors.blue("\Chain ID:", chainID));


        console.log(colors.blue("\nSigner address:", signer.address));
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
        const dataToAttest = [
            {
                name: "citationUID", value: [
                    ethers.encodeBytes32String("exampleUID1"),
                    ethers.encodeBytes32String("exampleUID2")
                ], type: "bytes32[]"
            },
            { name: "authorName", value: "OBob", type: "bytes32" },
            { name: "articleTitle", value: 'Why GM is new hello?!!', type: "string" },
            { name: "articleHash", value: 'random hash!!', type: "bytes32" },
            { name: "urlOfContent", value: "our-url-1", type: "string" }
        ]


        // main schema details
        // NOTE: CHANGE DATA HERE
        const recipient = signer.address;
        const attester = signer.address;
        const expirationTime = 0n;
        const revocable = false;
        //const stakeAmount = ethers.parseEther("0.0001");
        const stakeAmount = 0;
        const encodedData = schemaEncoder.encodeData(dataToAttest);
        console.log(colors.yellow("\nEncoded data:", encodedData));

        const domainSeparator = await eas.getDomainSeparator();
        const attestTypeHash = await eas.getAttestTypeHash();
        const version = await eas.getVersion();
        const nonce = await eas.getNonce(signer.address);
        console.log(colors.yellow("\nDomain separator:", domainSeparator));
        console.log(colors.yellow("\nAttest type hash:", attestTypeHash));
        console.log(colors.yellow("\nVersion:", version));

        const delegated = new Delegated({
            address: EASContractAddress,
            chainId: chainID,
            version: version,
        });
        console.log(colors.blue("\nCreating onchain attestation..."));
        try {
            console.log(colors.blue("\Signing the attestation..."));

            const delegatedAttestation = await delegated.signDelegatedAttestation(
                {
                    schema: taskArgs.schemaUid,
                    recipient: recipient,
                    expirationTime: expirationTime,
                    revocable: revocable,
                    refUID: ZERO_BYTES32,
                    data: encodedData,
                    value: stakeAmount,
                    deadline: 0,
                    nonce: nonce,
                },
                signer
            );

            //console.log("Delegated Attestation:", JSON.stringify(delegatedAttestation, replacer, 2));
            console.log(colors.blue("\Sending the signed attestation..."));

            const tx = await eas.attestByDelegation({
                schema: taskArgs.schemaUid,
                data: {
                    recipient: delegatedAttestation.message.recipient,
                    expirationTime: delegatedAttestation.message.expirationTime,
                    revocable:delegatedAttestation.message.revocable,
                    data: delegatedAttestation.message.data,
                    value: stakeAmount,
                },
                signature: {
                    r: delegatedAttestation.signature.r,
                    v: delegatedAttestation.signature.v,
                    s: delegatedAttestation.signature.s,
                },
                attester: attester,
                deadline: 0

            });

            const attestationUID = await tx.wait();
            // Append attestation UID to the file
            appendObjectToJsonFile(`${networkName}-attestations.json`, 'schemaUID: ' + taskArgs.schemaUid + ' attestationUID: ' + attestationUID);

            console.log(colors.green("\nOnchain Attestation successfully created!"));
            console.log(colors.yellow("\nAttestation UID:", attestationUID));
        } catch (error) {
            console.error(colors.red("\nError creating attestation:", error));
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
