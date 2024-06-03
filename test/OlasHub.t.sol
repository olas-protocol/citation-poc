// source .env & forge test --match-path test/OlasHub.t.sol -vvvv --fork-url $SEPOLIA_RPC_URL --via-ir
// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {Test, StdCheats, console} from "forge-std/Test.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEAS_V027, AttestationRequestData, AttestationRequest, DelegatedAttestationRequest} from "../src/interfaces/IEAS.sol"; // EAS_LEGACY is used for testing the Sepolia contract change that when testing another contract
import {Attestation, NO_EXPIRATION_TIME, Signature} from "eas-contracts/Common.sol";
import {ISchemaRegistry, SchemaRecord} from "eas-contracts/ISchemaRegistry.sol";
import {ISchemaResolver} from "eas-contracts/resolver/ISchemaResolver.sol";
import {IEAS} from "eas-contracts/IEAS.sol";
import {AuthorStake} from "../src/AuthorStake.sol";
import {OlasHub} from "../src/OlasHub.sol";

contract OlasHubTest is Test {
    using ECDSA for bytes32;
    // Contracts

    IEAS_V027 public eas;
    RoyaltyResolver public royaltyResolver;
    AuthorStake public authorStake;
    ISchemaRegistry public schemaRegistry;
    OlasHub public olasHub;

    address constant EAS_SEPOLIA_ADDRESS =
        0xC2679fBD37d54388Ce493F1DB75320D236e1815e;
    bytes32 ATTEST_TYPEHASH;
    bytes32 DOMAIN_SEPARATOR;
    bytes32 public registeredSchemaUID;

    address Alice;
    uint256 AlicePK;
    address Bob;
    uint256 BobPK;
    address Carla;
    uint256 CarlaPK;

    // Struct definitions

    struct OlasArticleSchema {
        address user;
        string title;
        bytes32 contentUrl;
        bytes32 mediaUrl;
        uint256 stakeAmount;
        uint256 royaltyAmount;
        MarketType typeOfMarket;
        bytes32[] citationUID;
    }

    // Enum definitions
    enum MarketType {
        NewsAndOpinion,
        InvestigativeJournalismAndScientific
    }

    // Event definitions
    event ProfileCreated(
        uint256 indexed profileId,
        address indexed userAddress,
        string userName,
        string userEmail,
        string profileImageUrl,
        uint256 profileCreationTimestamp
    );
    event ArticlePublished(
        bytes32 indexed attestationUID,
        address indexed attester,
        uint256 stakeAmount
    );

    function setUp() public {
        // deploy or fetch contracts
        (Alice, AlicePK) = makeAddrAndKey("Alice");
        (Bob, BobPK) = makeAddrAndKey("Bob");
        (Carla, CarlaPK) = makeAddrAndKey("Carla");
        eas = IEAS_V027(EAS_SEPOLIA_ADDRESS);
        authorStake = new AuthorStake();
        royaltyResolver = new RoyaltyResolver(
            IEAS(EAS_SEPOLIA_ADDRESS),
            address(authorStake)
        );
        ATTEST_TYPEHASH = eas.getAttestTypeHash();

        DOMAIN_SEPARATOR = eas.getDomainSeparator();
        schemaRegistry = eas.getSchemaRegistry();
        registeredSchemaUID = registerSchema();
        olasHub = new OlasHub(address(eas), registeredSchemaUID);
    }

    function test_AssertContractsDeployed() public view {
        assertTrue(address(eas) != address(0), "EAS contract not deployed");
        assertTrue(
            address(schemaRegistry) != address(0),
            "SchemaRegistry contract not fetched"
        );
        assertTrue(
            address(authorStake) != address(0),
            "AuthorStake contract not deployed"
        );
        assertTrue(
            address(royaltyResolver) != address(0),
            "RoyaltyResolver contract not deployed"
        );
        assertTrue(registeredSchemaUID != bytes32(0), "Schema not registered");
        assertTrue(ATTEST_TYPEHASH != bytes32(0), "AttestTypeHash not fetched");
        assertTrue(
            DOMAIN_SEPARATOR != bytes32(0),
            "DomainSeparator not fetched"
        );
    }

    function registerSchema() public returns (bytes32) {
        string
            memory schema = "address user string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount MarketType typeOfMarket bytes32[] citationUID";

        bool revocable = false;
        bytes32 schemaUID = schemaRegistry.register(
            schema,
            royaltyResolver,
            revocable
        );

        // fetch schema
        SchemaRecord memory schemaRecord = schemaRegistry.getSchema(schemaUID);
        assertEq(schemaRecord.uid, schemaUID, "Schema not registered");
        assertEq(
            schemaRecord.revocable,
            revocable,
            "Revocable not set correctly"
        );

        // compute UID manually and compare with the returned UID
        bytes32 computedUID = keccak256(
            abi.encodePacked(schema, address(royaltyResolver), revocable)
        );
        assertEq(schemaUID, computedUID, "UID not computed correctly");
        return schemaUID;
    }
    function test_CreateProfile() public {
        address callSigner = Alice;
        vm.startPrank(callSigner);
        bool hasProfileBefore = olasHub.hasProfile(callSigner);
        string memory userName = "Alice";
        string memory userEmail = "alice@olas.info";
        string memory profileImageUrl = "http://example.com/alice.jpg";
        assertFalse(
            hasProfileBefore,
            "Profile should not exist before creation"
        );
        olasHub.createProfile(userName, userEmail, profileImageUrl);
        assertTrue(
            olasHub.hasProfile(callSigner) == true,
            "Profile should exist after creation"
        );

        (
            uint256 profileId,
            string memory retrievedUserName,
            address userAddress,
            string memory retrievedUserEmail,
            string memory retrievedProfileImageUrl,
            uint256 profileCreationTimestamp
        ) = olasHub.profiles(callSigner);
        assertEq(retrievedUserName, userName, "User name should match");
        assertEq(retrievedUserEmail, userEmail, "User email should match");
        assertEq(
            retrievedProfileImageUrl,
            profileImageUrl,
            "Profile image URL should match"
        );
        vm.stopPrank();
    } 
    function test_DelegatedAttestation() public payable {
        // Create a profile
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);

        // Create a profile
        string memory userName = "Carla";
        string memory userEmail = "Carla@olas.info";
        string memory profileImageUrl = "http://example.com/carla.jpg";
        olasHub.createProfile(userName, userEmail, profileImageUrl);

        string memory title = "Sample Article";
        bytes32 contentUrl = keccak256(
            abi.encodePacked("http://example.com/content")
        );
        bytes32 mediaUrl = keccak256(
            abi.encodePacked("http://example.com/media")
        );
        uint256 stakeAmount = 0.1 ether;
        uint256 royaltyAmount = 0.001 ether;
        bytes32[] memory citationUID = new bytes32[](0);
        OlasHub.MarketType typeOfMarket = OlasHub.MarketType.NewsAndOpinion;
        bool revocable = false;

        // address user string title bytes32 contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount MarketType typeOfMarket bytes32[] citationUID
        bytes memory encodedData = abi.encode(
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: callSigner,
            expirationTime: 0,
            revocable: revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: stakeAmount
        });

        DelegatedAttestationRequest
            memory delegatedRequest = DelegatedAttestationRequest({
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

        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            Signature(v, r, s),
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        // check the attestation from the OlasHub contract
        assertEq(
            attestationUID,
            olasHub.authorArticles(callSigner, 0),
            "Attestation not stored correctly"
        );
        // check the attestation from the EAS contract
        Attestation memory fetchedAttestation = eas.getAttestation(
            attestationUID
        );

        assertEq(
            fetchedAttestation.schema,
            registeredSchemaUID,
            "Schema not set correctly"
        );
        assertEq(
            fetchedAttestation.recipient,
            callSigner,
            "Recipient not set correctly"
        );
        assertEq(
            fetchedAttestation.revocable,
            revocable,
            "Revocable not set correctly"
        );
        assertEq(
            fetchedAttestation.refUID,
            bytes32(0),
            "RefUID not set correctly"
        );
        assertEq(
            fetchedAttestation.data,
            encodedData,
            "Data not set correctly"
        );
        vm.stopPrank();
    }

    // HELPER FUNCTIONS
    function _getTypedHash(
        bytes32 structHash
    ) public view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
    }

    function _generateStructHash(
        DelegatedAttestationRequest memory request
    ) public view returns (bytes32) {
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

    function _verifySignature(
        bytes32 digest,
        Signature memory signature,
        address signer
    ) public view {
        if (
            ECDSA.recover(digest, signature.v, signature.r, signature.s) !=
            signer
        ) {
            revert("Invalid signature");
        }
    }
}
