// source .env & forge test --match-path test/OlasHub.t.sol -vvvv --fork-url $SEPOLIA_RPC_URL --via-ir
// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {Test, StdCheats, console} from "forge-std/Test.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";
import {OlasHub} from "../src/OlasHub.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {NO_EXPIRATION_TIME, Signature} from "eas-contracts/Common.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {
    IEAS,
    Attestation,
    AttestationRequestData,
    AttestationRequest,
    DelegatedAttestationRequest,
    EIP712Signature
} from "../src/interfaces/eas-v026/IEAS.sol";
import {EIP712Verifier} from "../src/eip712/EIP712Verifier.sol";
import {ISchemaRegistry, SchemaRecord} from "../src/interfaces/eas-v026/ISchemaRegistry.sol";
import {ISchemaResolver} from "../src/interfaces/eas-v026/ISchemaResolver.sol";

contract OlasHubTest is Test, EIP712Verifier("1.3.0") {
    // Contracts
    using ECDSA for bytes32;

    RoyaltyResolver public royaltyResolver;
    bytes32 public registeredSchemaUID;
    OlasHub public olasHub;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;
    address constant EAS_SEPOLIA_ADDRESS = 0xC2679fBD37d54388Ce493F1DB75320D236e1815e;

    // Enum definitions
    enum Status {
        Review,
        Published
    }

    enum MarketType {
        NewsAndOpinion,
        InvestigativeJournalismAndScientific
    }

    address Alice;
    uint256 AlicePK;
    address Bob;
    uint256 BobPK;
    address Carla;
    uint256 CarlaPK;

    uint256 testerPKey;
    address tester;

    bytes32 private constant ATTEST_TYPEHASH_LEGACY = 0xdbfdf8dc2b135c26253e00d5b6cbe6f20457e003fd526d97cea183883570de61;
    bytes32 private constant ATTEST_TYPEHASH_V1 = 0xf83bb2b0ede93a840239f7e701a54d9bc35f03701f51ae153d601c6947ff3d3f;
    bytes32 private constant ATTEST_TYPEHASH_V2 = 0xfeb2925a02bae3dae48d424a0437a2b6ac939aa9230ddc55a1a76f065d988076;

    struct OlasArticleSchema {
        address user; // Using OlasHub.userProfiles mapping user details can be retrieved
        string title; // The title of the article
        bytes32 contentUrl; // A url pointing to the article content
        bytes32 mediaUrl; // A url pointing to the media used in the article
        uint256 stakeAmount; // The total amount of staked ether by the article
        uint256 royaltyAmount; // The total amount of royalty paid by the article
        bytes32[] citationUID; // An array of citation UIDs
    }

    function setUp() public {
        // deploy or fetch contracts
        (Alice, AlicePK) = makeAddrAndKey("Alice");
        (Bob, BobPK) = makeAddrAndKey("Bob");
        (Carla, CarlaPK) = makeAddrAndKey("Carla");
        (tester, testerPKey) = makeAddrAndKey("tester");

        eas = IEAS(EAS_SEPOLIA_ADDRESS);

        schemaRegistry = eas.getSchemaRegistry();
        registeredSchemaUID = registerSchema();
        console.log("Registered Schema UID");
        console.logBytes32(registeredSchemaUID);
        console.log("Fetched SchemaRegistry address");
        console.logAddress(address(schemaRegistry));
    }

    function test_AssertContractsDeployed() public {
        assertTrue(address(eas) != address(0), "EAS contract not deployed");
        assertTrue(address(schemaRegistry) != address(0), "SchemaRegistry contract not fetched");
    }

    function registerSchema() public returns (bytes32) {
        string memory schema =
            "string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32[] citationUIDs";
        bool revocable = false;
        bytes32 schemaUID = schemaRegistry.register(schema, ISchemaResolver(address(0)), revocable);
        // fetch schema
        SchemaRecord memory schemaRecord = schemaRegistry.getSchema(schemaUID);
        assertEq(schemaRecord.uid, schemaUID, "Schema not registered");

        assertEq(schemaRecord.revocable, revocable, "Revocable not set correctly");
        // compute UID manually and compare with the returned UID
        bytes32 computedUID = keccak256(abi.encodePacked(schema, address(0), revocable));
        assertEq(schemaUID, computedUID, "UID not computed correctly");
        return schemaUID;
    }

    function test_delegatedAttestation() public payable {
        // Create a profile
        address callSigner = tester;
        uint256 callSignerPK = testerPKey;
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);

        string memory title = "Sample Article";
        bytes32 contentUrl = keccak256(abi.encodePacked("http://example.com/content"));
        bytes32 mediaUrl = keccak256(abi.encodePacked("http://example.com/media"));
        uint256 stakeAmount = 0.1 ether;
        uint256 royaltyAmount = 0.001 ether;
        bytes32[] memory citationUIDs = new bytes32[](0);
        uint64 deadline = 0;
        bool revocable = false;

        // string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32[] citationUIDs
        bytes memory encodedData = abi.encode(title, contentUrl, mediaUrl, stakeAmount, royaltyAmount, citationUIDs);
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: callSigner,
            expirationTime: NO_EXPIRATION_TIME,
            revocable: revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: 0
        });

        DelegatedAttestationRequest memory delegatedRequest = DelegatedAttestationRequest({
            schema: registeredSchemaUID,
            data: requestData,
            signature: EIP712Signature(0, bytes32(0), bytes32(0)), // Placeholder
            attester: callSigner
        });

        // Generate the correct signature
        bytes32 digest = getHashTypedDataV4(delegatedRequest);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(callSignerPK, digest);
        address signer = ecrecover(digest, v, r, s);
        assertEq(callSigner, signer, "Signer could not be derived from the signature...");
        console.log("Recovered Signer");
        console.logAddress(signer);
        //  Signature memory signature = Signature(v, r, s);
        delegatedRequest.signature = EIP712Signature(v, r, s);

        _verifyAttest(delegatedRequest);

        address eRecoveredSigner = ECDSA.recover(digest, v, r, s);
        if (eRecoveredSigner != callSigner) {
            revert("Invalid Signature ECDSA.recover");
        }
        console.log("eRecoveredSigner");
        console.logAddress(eRecoveredSigner);

        bytes memory signature = abi.encodePacked(r, s, v);
        (address recovered, ECDSA.RecoverError recoverError, bytes32 result) = ECDSA.tryRecover(digest, v, r, s);

        assertEq(recovered, callSigner, "Recovered address does not match the signer");

        console.log("schemaUID");
        console.logBytes32(registeredSchemaUID);
        console.log("recipient");
        console.logAddress(requestData.recipient);
        console.log("expirationTime");
        console.logUint(requestData.expirationTime);
        console.log("revocable");
        console.logBool(requestData.revocable);
        console.log("refUID");
        console.logBytes32(requestData.refUID);
        console.log("data");
        console.logBytes(requestData.data);
        console.log("value");
        console.logUint(requestData.value);
        console.log("signature.v");
        console.logUint(v);
        console.log("signature.r");
        console.logBytes32(r);
        console.log("signature.s");
        console.logBytes32(s);

        //eas.attestByDelegation{value: 0}(delegatedRequest);

        //AttestationRequest memory sendRequest = AttestationRequest({schema: registeredSchemaUID, data: requestData});
        //eas.attest(sendRequest);
        vm.stopPrank();
    }
}
