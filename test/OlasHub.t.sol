// source .env & forge test --match-path test/OlasHub.t.sol -vvvv --fork-url $SEPOLIA_RPC_URL --via-ir
// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {Test, StdCheats, console} from "forge-std/Test.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";
//import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {
    IEAS,
    AttestationRequestData,
    AttestationRequest,
    DelegatedAttestationRequest
} from "../src/interfaces/IEAS_LEGACY.sol"; // EAS_LEGACY is used for testing the Sepolia contract change that when testing another contract
import {Attestation, NO_EXPIRATION_TIME, Signature} from "eas-contracts/Common.sol";

import {ISchemaRegistry, SchemaRecord} from "eas-contracts/ISchemaRegistry.sol";
import {ISchemaResolver} from "eas-contracts/resolver/ISchemaResolver.sol";

contract OlasHubTest is Test {
    // Contracts
    using ECDSA for bytes32;

    RoyaltyResolver public royaltyResolver;
    bytes32 public registeredSchemaUID;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;
    address constant EAS_SEPOLIA_ADDRESS = 0xC2679fBD37d54388Ce493F1DB75320D236e1815e;
    bytes32 ATTEST_TYPEHASH;
    bytes32 DOMAIN_SEPARATOR;
    address Alice;
    uint256 AlicePK;
    address Bob;
    uint256 BobPK;
    address Carla;
    uint256 CarlaPK;

    uint256 testerPKey;
    address tester;

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
        ATTEST_TYPEHASH = eas.getAttestTypeHash();

        DOMAIN_SEPARATOR = eas.getDomainSeparator();
        schemaRegistry = eas.getSchemaRegistry();
        registeredSchemaUID = registerSchema();
    }

    function test_AssertContractsDeployed() public view {
        assertTrue(address(eas) != address(0), "EAS contract not deployed");
        assertTrue(address(schemaRegistry) != address(0), "SchemaRegistry contract not fetched");
        assertTrue(registeredSchemaUID != bytes32(0), "Schema not registered");
        assertTrue(ATTEST_TYPEHASH != bytes32(0), "AttestTypeHash not fetched");
        assertTrue(DOMAIN_SEPARATOR != bytes32(0), "DomainSeparator not fetched");
    }

    function registerSchema() public returns (bytes32) {
        string memory schema =
            "string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32[] citationUID";
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

    function test_DelegatedAttestation() public payable {
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
        bytes32[] memory citationUID = new bytes32[](0);
        uint64 deadline = 0;
        bool revocable = false;

        // string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32[] citationUID
        bytes memory encodedData = abi.encode(title, contentUrl, mediaUrl, stakeAmount, royaltyAmount, citationUID);
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: callSigner,
            expirationTime: deadline,
            revocable: revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: 0
        });

        DelegatedAttestationRequest memory delegatedRequest = DelegatedAttestationRequest({
            schema: registeredSchemaUID,
            data: requestData,
            signature: Signature(0, bytes32(0), bytes32(0)), // Placeholder
            attester: callSigner
        });

        // Generate the correct signature
        bytes32 structHash = _generateStructHash(delegatedRequest);
        bytes32 digest = _getTypedHash(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(callSignerPK, digest);

        _verifySignature(digest, Signature(v, r, s), callSigner);
        delegatedRequest.signature = Signature(v, r, s);
        bytes32 UID = eas.attestByDelegation(delegatedRequest);

        vm.stopPrank();
    }

    // HELPER FUNCTIONS
    function _getTypedHash(bytes32 structHash) public view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
    }

    function _generateStructHash(DelegatedAttestationRequest memory request) public view returns (bytes32) {
        AttestationRequestData memory data = request.data;
        uint256 nonce = eas.getNonce(request.attester);
        bytes32 structHash = keccak256(
            abi.encode(
                ATTEST_TYPEHASH,
                request.schema,
                data.recipient,
                data.expirationTime,
                data.revocable,
                data.refUID,
                keccak256(data.data),
                nonce
            )
        );
        return structHash;
    }
    //

    function _verifySignature(bytes32 digest, Signature memory signature, address signer) public view {
        if (ECDSA.recover(digest, signature.v, signature.r, signature.s) != signer) {
            revert("Invalid signature");
        }
    }
}
