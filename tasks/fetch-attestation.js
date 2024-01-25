// npx hardhat fetch-attestation --attestation-uid <ATTESTATION_UID> --network <NETWORK_NAME>
// npx hardhat  fetch-attestation --attestation-uid "0xBD337FF23D43B8EF57EBBF78B90AA3B3E21129191FCF0E587CD267ABFC054779" --network sepolia
const { EAS } = require("@ethereum-attestation-service/eas-sdk");
const colors = require('colors');

task("fetch-attestation", "Fetches the attestation data")
    .addParam("attestationUid", "The ID of the attestation")
    .setAction(async (taskArgs, hre) => {
        const accounts = await hre.ethers.getSigners();
        const signer = accounts[0];
        const EASContractAddress = process.env.EAS_ADDRESS_SEPOLIA;
        const eas = new EAS(EASContractAddress);
        eas.connect(signer);

        try {
            const attestation = await eas.getAttestation(taskArgs.attestationUid);
            if (attestation[0] === "0x0000000000000000000000000000000000000000000000000000000000000000") {
                console.log(colors.red("\No attestation found with the given UID"));
            }
            else {
                console.log(colors.green("\nAttestation fetched successfully: ", attestation));
            }
        } catch (error) {
            console.log(colors.red("\nError fetching attestation:", error));
        }
    });

