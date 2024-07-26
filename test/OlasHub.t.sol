// source .env & forge test --match-path test/OlasHub.t.sol -vvvv --via-ir --fork-url $SEPOLIA_RPC_URL
// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {Test, StdCheats, console} from "forge-std/Test.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEAS_V026, AttestationRequestData, AttestationRequest, DelegatedAttestationRequest} from "../src/interfaces/IEAS.sol"; // EAS_LEGACY is used for testing the Sepolia contract change that when testing another contract
import {Attestation, NO_EXPIRATION_TIME, Signature} from "eas-contracts/Common.sol";
import {ISchemaRegistry, SchemaRecord} from "eas-contracts/ISchemaRegistry.sol";
import {ISchemaResolver} from "eas-contracts/resolver/ISchemaResolver.sol";
import {IEAS} from "eas-contracts/IEAS.sol";
import {AuthorStake} from "../src/AuthorStake.sol";
import {OlasHub} from "../src/OlasHub.sol";

contract OlasHubTest is Test {
    using ECDSA for bytes32;
    /*//////////////////////////////////////////////////////////////
                               Contracts
    //////////////////////////////////////////////////////////////*/
    IEAS_V026 public eas;
    RoyaltyResolver public royaltyResolver;
    AuthorStake public authorStake;
    ISchemaRegistry public schemaRegistry;
    OlasHub public olasHub;

    /*//////////////////////////////////////////////////////////////
                               Constants
    //////////////////////////////////////////////////////////////*/
    bytes32 constant NEWS_AND_OPINION = keccak256("NewsAndOpinion");
    bytes32 constant INVESTIGATIVE_JOURNALISM_AND_SCIENTIFIC =
        keccak256("InvestigativeJournalismAndScientific");
    address constant EAS_SEPOLIA_ADDRESS =
        0xC2679fBD37d54388Ce493F1DB75320D236e1815e;

    // Variables fetched from the EAS contract
    bytes32 ATTEST_TYPEHASH;
    bytes32 DOMAIN_SEPARATOR;

    bytes32 registeredSchemaUID;

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
        string contentUrl;
        bytes32 mediaUrl;
        uint256 stakeAmount;
        uint256 royaltyAmount;
        bytes32 typeOfMarket;
        bytes32[] citationUID;
    }

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
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
        eas = IEAS_V026(EAS_SEPOLIA_ADDRESS);
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

    function test_CreateProfile() public {
        address callSigner = Alice;
        string memory userName = "Alice";
        string memory userEmail = "alice@olas.info";
        string memory profileImageUrl = "http://example.com/alice.jpg";

        vm.startPrank(callSigner);

        // Assert that the profile does not exist before creation
        assertFalse(
            olasHub.hasProfile(callSigner),
            "Profile should not exist before creation"
        );

        olasHub.createProfile(userName, userEmail, profileImageUrl);
        // Assert that the profile exists after creation
        assertTrue(
            olasHub.hasProfile(callSigner),
            "Profile should exist after creation"
        );

        (
            uint256 profileId,
            string memory retrievedUserName,
            address userAddress,
            string memory retrievedUserEmail,
            string memory retrievedProfileImageUrl
        ) = olasHub.profiles(callSigner);

        // Assert Profile struct data
        assertEq(retrievedUserName, userName, "User name should match");
        assertEq(retrievedUserEmail, userEmail, "User email should match");
        assertEq(
            retrievedProfileImageUrl,
            profileImageUrl,
            "Profile image URL should match"
        );
        vm.stopPrank();
    }

    function test_Publish() public payable {
        // Profile details
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        (
            string memory userName,
            string memory userEmail,
            string memory profileImageUrl
        ) = _dummyProfileDetails();

        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);
        // Create a profile
        _createProfile(callSigner, userName, userEmail, profileImageUrl);

        // Article details
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, new bytes32[](0));

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
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
        vm.stopPrank();
    }
    function test_PublishByDifferentCaller() public payable {
        // Publishing an article by a different caller
        address callSigner = Carla;
        address functionCaller = Bob;
        uint256 callSignerPK = CarlaPK;
        (
            string memory userName,
            string memory userEmail,
            string memory profileImageUrl
        ) = _dummyProfileDetails();

        vm.deal(callSigner, 100 ether);
        vm.deal(functionCaller, 100 ether);

        vm.startPrank(callSigner);
        // Create a profile
        _createProfile(callSigner, userName, userEmail, profileImageUrl);

        // Article details
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, new bytes32[](0));

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        vm.stopPrank();
        vm.startPrank(functionCaller); // start the prank for the different caller

        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
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
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               FAIL CASES
    //////////////////////////////////////////////////////////////*/
    function test_InvalidSigner() public {
        // publishing an article with an invalid attester
        address callSigner = Carla;
        address invalidSigner = Bob;
        uint256 callSignerPK = CarlaPK;

        // Create a profile for the invalid signer
        vm.startPrank(invalidSigner);
        _createProfile(
            invalidSigner,
            "Bob",
            "Bob@olas.info",
            "http://example.com/Bob.jpg"
        );
        vm.stopPrank(); // stop the prank for the invalid signer

        // Create a profile for the valid signer
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);
        _createProfile(
            callSigner,
            "Carla",
            "Carla@olas.info",
            "http://example.com/carla.jpg"
        );

        // Article details
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, new bytes32[](0));

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        // InvalidSignature() selector
        bytes4 INVALID_SIGNATURE = bytes4(keccak256("InvalidSignature()"));

        // Attempt to publish with invalid signer than the one who signed the attestation
        vm.expectRevert(INVALID_SIGNATURE);
        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
            invalidSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        vm.stopPrank();
    }
    function test_InvalidMarketType() public {
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);
        // Create a profile
        _createProfile(
            callSigner,
            "Carla",
            "Carla@olas.info",
            "http://example.com/carla.jpg"
        );

        // Article details
        // publishing an article with an invalid market type
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(
                keccak256("InvalidMarketTypeHash"),
                new bytes32[](0)
            );

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        // Attempt to publish with invalid market type bytes32
        vm.expectRevert("Invalid market type");
        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        vm.stopPrank();
    }

    function test_InvalidStakeAmount() public {
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);
        // Create a profile
        _createProfile(
            callSigner,
            "Carla",
            "Carla@olas.info",
            "http://example.com/carla.jpg"
        );

        // Article details
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, new bytes32[](0));
        uint256 differentStakeAmount = 0.01 ether;

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        // Attempt to publish with a different stake amount
        vm.expectRevert("Invalid stake amount");
        bytes32 attestationUID = olasHub.publish{value: differentStakeAmount}(
            delegatedRequest.signature,
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        vm.stopPrank();
    }

    function test_InvalidCitationUID() public {
        // publishing an article with an invalid citation UID
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        (
            string memory userName,
            string memory userEmail,
            string memory profileImageUrl
        ) = _dummyProfileDetails();

        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);
        // Create a profile
        _createProfile(callSigner, userName, userEmail, profileImageUrl);

        // Article details with invalid citation UID
        bytes32 randomCitation = keccak256("random byte32");
        bytes32[] memory invalidCitationUIDArray = new bytes32[](1);
        invalidCitationUIDArray[0] = randomCitation;
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, invalidCitationUIDArray);

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        vm.expectRevert(RoyaltyResolver.InvalidCitationUID.selector);
        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        vm.stopPrank();
    }
    function test_AttestationWithoutProfile() public {
        address callSigner = Carla;
        uint256 callSignerPK = CarlaPK;
        vm.deal(callSigner, 100 ether);
        vm.startPrank(callSigner);

        // Article details
        (
            string memory title,
            string memory contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32[] memory citationUID,
            bytes32 typeOfMarket,
            bool revocable
        ) = _dummyPublishArgs(NEWS_AND_OPINION, new bytes32[](0));

        DelegatedAttestationRequest
            memory delegatedRequest = _generateDelegatedAttestationRequest(
                callSigner,
                title,
                contentUrl,
                mediaUrl,
                stakeAmount,
                royaltyAmount,
                citationUID,
                typeOfMarket,
                revocable
            );

        // Generate the correct signature
        delegatedRequest.signature = _verifyAndReturnSignature(
            delegatedRequest,
            callSigner,
            callSignerPK
        );

        // Attempt to publish article without creating a profile
        vm.expectRevert("Profile does not exist");
        bytes32 attestationUID = olasHub.publish{value: stakeAmount}(
            delegatedRequest.signature,
            callSigner,
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            typeOfMarket,
            citationUID
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function registerSchema() private returns (bytes32) {
        string
            memory schema = "address user string title string contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32 typeOfMarket bytes32[] citationUID";

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

    function _getTypedHash(bytes32 structHash) private view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
    }

    function _generateStructHash(
        DelegatedAttestationRequest memory request
    ) private view returns (bytes32) {
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
    ) private pure {
        if (
            ECDSA.recover(digest, signature.v, signature.r, signature.s) !=
            signer
        ) {
            revert("Invalid signature");
        }
    }

    function _createProfile(
        address _user,
        string memory userName,
        string memory userEmail,
        string memory profileImageUrl
    ) private {
        // Assert that the profile does not exist before creation
        assertFalse(
            olasHub.hasProfile(_user),
            "Profile should not exist before creation"
        );

        olasHub.createProfile(userName, userEmail, profileImageUrl);
        // Assert that the profile exists after creation
        assertTrue(
            olasHub.hasProfile(_user),
            "Profile should exist after creation"
        );

        (
            uint256 profileId,
            string memory retrievedUserName,
            address userAddress,
            string memory retrievedUserEmail,
            string memory retrievedProfileImageUrl
        ) = olasHub.profiles(_user);

        // Assert Profile struct data
        assertEq(retrievedUserName, userName, "User name should match");
        assertEq(retrievedUserEmail, userEmail, "User email should match");
        assertEq(
            retrievedProfileImageUrl,
            profileImageUrl,
            "Profile image URL should match"
        );
    }
    function _generateDelegatedAttestationRequest(
        address _user,
        string memory _title,
        string memory _contentUrl,
        bytes32 _mediaUrl,
        uint256 _stakeAmount,
        uint256 _royaltyAmount,
        bytes32[] memory _citationUID,
        bytes32 _typeOfMarket,
        bool _revocable
    ) private view returns (DelegatedAttestationRequest memory) {
        // address user string title string contentUrl bytes32 mediaUrl uint256 stakeAmount uint256 royaltyAmount bytes32 typeOfMarket bytes32[] citationUID
        bytes memory encodedData = abi.encode(
            _user,
            _title,
            _contentUrl,
            _mediaUrl,
            _stakeAmount,
            _royaltyAmount,
            _typeOfMarket,
            _citationUID
        );

        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: _user,
            expirationTime: 0,
            revocable: _revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: _stakeAmount
        });

        DelegatedAttestationRequest
            memory delegatedRequest = DelegatedAttestationRequest({
                schema: registeredSchemaUID,
                data: requestData,
                signature: Signature(0, bytes32(0), bytes32(0)), // Placeholder
                attester: _user
            });
        return delegatedRequest;
    }

    function _dummyProfileDetails()
        private
        pure
        returns (string memory, string memory, string memory)
    {
        string memory userName = "Carla";
        string memory userEmail = "Carla@olas.info";
        string memory profileImageUrl = "http://example.com/carla.jpg";

        return (userName, userEmail, profileImageUrl);
    }

    function _dummyPublishArgs(
        bytes32 typeOfMarket,
        bytes32[] memory citationUID
    )
        private
        pure
        returns (
            string memory,
            string memory,
            bytes32,
            uint256,
            uint256,
            bytes32[] memory,
            bytes32,
            bool
        )
    {
        string memory title = "Sample Article";
        string memory contentUrl = "http://example.com/content";
        bytes32 mediaUrl = keccak256(
            abi.encodePacked("http://example.com/media")
        );
        uint256 stakeAmount = 0.1 ether;
        uint256 royaltyAmount = 0.001 ether;
        bool revocable = false;
        return (
            title,
            contentUrl,
            mediaUrl,
            stakeAmount,
            royaltyAmount,
            citationUID,
            typeOfMarket,
            revocable
        );
    }

    function _verifyAndReturnSignature(
        DelegatedAttestationRequest memory delegatedRequest,
        address signerAddress,
        uint256 signerPrivateKey
    ) private view returns (Signature memory) {
        bytes32 structHash = _generateStructHash(delegatedRequest);
        bytes32 digest = _getTypedHash(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        _verifySignature(digest, Signature(v, r, s), signerAddress);
        return Signature(v, r, s);
    }
}
