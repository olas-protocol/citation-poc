// npx hardhat create-delegated-attestation --schema-uid <SCHEMA-UID> --network <NETWORK_NAME>
// npx hardhat create-delegated-attestation --schema-uid  0xf4ea9ac884bca53c4831e8f598bd20ac6f0e57a5572a032f34b1bcf66bc82ba2  --network sepolia
// NOTE: change data to attest to before running script
const { types, task } = require("hardhat/config");
const fs = require('fs');
const colors = require('colors');
const { SchemaEncoder, EAS, Delegated, ZERO_BYTES32 } = require("@ethereum-attestation-service/eas-sdk");
const { ethers } = require("ethers");
const OlasHub_ABI = require("../src/abis/OlasHub_ABI.json");
task("create-delegated-attestation", "Creates an attestation")
    .addParam("schemaUid", "Schema which you want to use for attestation")
    .addOptionalParam("useOlasHub", "Use OlasHub contract for attestation", true, types.boolean)
    .setAction(async (taskArgs) => {
        const { run, network } = require('hardhat');
        const networkName = network.name;
        const chainID = network.config.chainId;
        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];

        console.log(colors.bold("\n==> Running create-delegated-attestation task..."));
        console.log(colors.blue("\nNetwork:", networkName));
        console.log(colors.blue("\Chain ID:", chainID));
        console.log(colors.blue("\nSigner address:", signer.address));


        const EASContractAddress = process.env.EAS_ADDRESS_SEPOLIA;
        const OlasHubContractAddress = process.env.OLAS_HUB_SEPOLIA;
        const eas = new EAS(EASContractAddress);
        eas.connect(signer);

        // OlasHub contract
        const olasHub = new ethers.Contract(OlasHubContractAddress, OlasHub_ABI, signer);
        if (!(await olasHub.hasProfile(signer.address))) {
            console.log(colors.red("\nUser does not have a profile, exiting..."));
            return;
        }

        // bytes32 market types 
        const NEWS_AND_OPINION = ethers.keccak256(ethers.toUtf8Bytes("NewsAndOpinion"));
        const INVESTIGATIVE_JOURNALISM_AND_SCIENTIFIC = ethers.keccak256(ethers.toUtf8Bytes("InvestigativeJournalismAndScientific"));


        console.log(colors.blue("\nTrying to fetch schema for uid:", taskArgs.schemaUid));
        const fetchedSchema = await run("fetch-schema", { uid: taskArgs.schemaUid });
        if (fetchedSchema === null) {
            console.log(colors.red("\nSchema does not exist, exiting..."));
            return;
        }

        // initialize schemaEncoder with schema string
        const schemaEncoder = new SchemaEncoder(fetchedSchema.schema);
        //  --------------------- NOTE: CHANGE DATA HERE ---------------------
        const title = "Why GM is new hello?!!";
        const contentUrl = ethers.encodeBytes32String("random content url");
        const mediaUrl = ethers.encodeBytes32String("random media url");
        const typeOfMarket = NEWS_AND_OPINION;
        const citationUID = ["0x89e20a1a67336e4fffbb3cd26e229a82e9c6b6619ed2485b69a7a6444861249b"
        ];
        const stakeAmount = ethers.parseEther("0.0001");
        const recipient = signer.address;
        const attester = signer.address;
        const expirationTime = 0n;
        const revocable = false;
        const royaltyAmount = 0;


        const dataToAttest = [
            { name: "user", value: signer.address, type: "address" },
            { name: "title", value: title, type: "string" },
            { name: "contentUrl", value: contentUrl, type: "bytes32" },
            { name: "mediaUrl", value: mediaUrl, type: "bytes32" },
            { name: "stakeAmount", value: stakeAmount, type: "uint256" },
            { name: "royaltyAmount", value: royaltyAmount, type: "uint256" },
            { name: "typeOfMarket", value: typeOfMarket, type: "bytes32" },
            {
                name: "citationUID", value: citationUID, type: "bytes32[]"
            }
        ]

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
                    revocable: false,
                    refUID: ZERO_BYTES32,
                    data: encodedData,
                    value: stakeAmount,
                    deadline: 0,
                    nonce: nonce,
                },
                signer
            );
            console.log(colors.blue("\Sending the signed attestation..."));

            if (taskArgs.useOlasHub) {
                console.log(colors.yellow("\Using OlasHub contract for attestation"));

                const tx = await olasHub.publish({
                    v: delegatedAttestation.signature.v,
                    r: delegatedAttestation.signature.r,
                    s: delegatedAttestation.signature.s,
                },
                    recipient,
                    title,
                    contentUrl,
                    mediaUrl,
                    stakeAmount,
                    royaltyAmount,
                    typeOfMarket,
                    citationUID
                    , { value: stakeAmount });



                // Get the events from tx and check manually
                // Get the events from tx and check manually
                const receipt = await tx.wait();
                const events = await olasHub.queryFilter(olasHub.filters.ArticlePublished, receipt.blockNumber, receipt.blockNumber)
                const attestationUID = events[0].args[0];
                // Append attestation UID to the file
                appendObjectToJsonFile(`${networkName}-attestations.json`, 'schemaUID: ' + taskArgs.schemaUid + ' attestationUID: ' + attestationUID);

                console.log(colors.green("\n Attestation successfully created!"));
                console.log(colors.yellow("\nAttestation UID:", attestationUID));

            }
            else {
                console.log(colors.yellow("\Using EAS contract for attestation"));
                const tx = await eas.attestByDelegation({
                    schema: taskArgs.schemaUid,
                    data: {
                        recipient: delegatedAttestation.message.recipient,
                        expirationTime: delegatedAttestation.message.expirationTime,
                        revocable: delegatedAttestation.message.revocable,
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
                console.log(colors.green("\Attestation successfully created!"));
                console.log(colors.yellow("\nAttestation UID:", attestationUID));

            }


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

