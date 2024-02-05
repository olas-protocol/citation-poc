// source .env & forge test --match-path test/RoyaltyResolver.t.sol -vvvv --fork-url $SEPOLIA_RPC_URL --via-ir
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EAS, Attestation, AttestationRequestData, AttestationRequest} from "eas-contracts/EAS.sol";
import {ISchemaRegistry, SchemaRecord} from "eas-contracts/ISchemaRegistry.sol";
import {AuthorStake} from "../src/AuthorStake.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";

contract RoyaltyResolverTest is Test {
    // Contracts
    RoyaltyResolver public royaltyResolver;
    EAS public eas;
    AuthorStake public authorStake;
    ISchemaRegistry public schemaRegistry;

    // Variables
    address Alice = address(1);
    address Bob = address(2);
    address Carla = address(3);
    bytes32[] private registeredSchemaUIDs;
    uint256 ROYALTY_PERCENTAGE = 10;

    struct CustomAttestationSchema {
        bytes32[] citationUID; // An array of citation UIDs
        bytes32 authorName; // The author's name
        string articleTitle; // The title of the article
        bytes32 articleHash; // A hash of the article content
        string urlOfContent; // The URL where the content can be accessed
    }

    function setUp() public {
        // deploy or fetch contracts
        eas = EAS(0xC2679fBD37d54388Ce493F1DB75320D236e1815e);
        authorStake = new AuthorStake();
        royaltyResolver = new RoyaltyResolver(eas, address(authorStake));
        schemaRegistry = eas.getSchemaRegistry();

        registerSchema();
    }

    function testAssertContractsDeployed() public {
        assertTrue(address(eas) != address(0), "EAS contract not deployed");
        assertTrue(
            address(authorStake) != address(0),
            "AuthorStake contract not deployed"
        );
        assertTrue(
            address(royaltyResolver) != address(0),
            "RoyaltyResolver contract not deployed"
        );
        assertTrue(
            address(schemaRegistry) != address(0),
            "SchemaRegistry contract not fetched"
        );
    }

    function registerSchema() public {
        string
            memory schema = "bytes32[] citationUID bytes32 authorName string articleTitle bytes32 articleHash string urlOfContent";
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
            address(schemaRecord.resolver),
            address(royaltyResolver),
            "Resolver not set"
        );
        assertEq(
            schemaRecord.revocable,
            revocable,
            "Revocable not set correctly"
        );
        // compute UID manually and compare with the returned UID
        bytes32 computedUID = keccak256(
            abi.encodePacked(schema, royaltyResolver, revocable)
        );
        registeredSchemaUIDs.push(schemaUID);
        assertEq(schemaUID, computedUID, "UID not computed correctly");
    }

    // helper function to generate attestation request to be used in attest function
    function generateAttestationRequest(
        address attesterAddress,
        bytes32[] memory citationUIDs,
        bytes32 authorName,
        string memory articleTitle,
        bytes32 articleHash,
        string memory urlOfContent,
        uint256 stakeValue
    ) public view returns (AttestationRequest memory) {
        // attest(AttestationRequest calldata request)
        uint64 timeToExpire = 0;
        bool revocable = false;
        // encode data
        bytes memory encodedData = abi.encode(
            citationUIDs,
            authorName,
            articleTitle,
            articleHash,
            urlOfContent
        );

        // Create an instance of AttestationRequestData with hardcoded values
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: attesterAddress,
            expirationTime: timeToExpire,
            revocable: revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: stakeValue
        });
        bytes32 schemaUID = registeredSchemaUIDs[0];
        AttestationRequest memory attestationRequest = AttestationRequest({
            schema: schemaUID,
            data: requestData
        });
        return attestationRequest;
    }

    // helper function to calculate royalties according to the formulas in the contract
    function calculateRoyalties(
        uint256 stakeValue,
        uint256 citationCount
    )
        public
        view
        returns (
            uint256 totalRoyalty,
            uint256 individualRoyalty,
            uint256 expectedStakingAmount
        )
    {
        if (citationCount == 0) {
            // If there are no citations, no royalties are distributed.
            totalRoyalty = 0;
            individualRoyalty = 0;
        } else {
            totalRoyalty = (stakeValue * ROYALTY_PERCENTAGE) / 100;
            individualRoyalty = totalRoyalty / citationCount;
        }
        expectedStakingAmount = stakeValue - totalRoyalty;
        return (totalRoyalty, individualRoyalty, expectedStakingAmount);
    }

    // Testing custom errors
    function testInsufficientEthValueForEAS() public {
        AttestationRequest memory request = generateAttestationRequest(
            Alice,
            new bytes32[](0),
            bytes32("authorName"),
            "Article Title",
            bytes32("articleHash"),
            "http://example.com",
            1 ether
        );
        vm.deal(Alice, 1 ether);
        vm.prank(Alice);

        vm.expectRevert(EAS.InsufficientValue.selector);
        // Sending less ether than required
        eas.attest{value: 0}(request);
    }

    function testInsufficientEthValueSentForRoyaltyResolver() public {
        AttestationRequest memory request = generateAttestationRequest(
            Alice,
            new bytes32[](0),
            bytes32("authorName"),
            "Article Title",
            bytes32("articleHash"),
            "http://example.com",
            // sending 0 value
            0
        );
        vm.prank(Alice);
        vm.deal(Alice, 1 ether);
        vm.expectRevert(RoyaltyResolver.InsufficientEthValueSent.selector);
        eas.attest{value: 0}(request);
    }

    function testInvalidCitationUID() public {
        bytes32 invalidCitationUID = keccak256("clearlyInvalidUID");

        bytes32[] memory citationUIDs = new bytes32[](1);
        // Invalid UID
        citationUIDs[0] = invalidCitationUID;
        uint256 stakeValue = 0.5 ether;
        AttestationRequest memory request = generateAttestationRequest(
            Alice,
            citationUIDs,
            bytes32("authorName"),
            "Article Title",
            bytes32("articleHash"),
            "http://example.com",
            stakeValue
        );

        vm.prank(Alice);
        vm.expectRevert();
        eas.attest{value: stakeValue}(request);
    }

    function testDirectPaymentsNotAllowed() public {
        // Send ETH directly to the contract without calling a function and expect revert
        vm.deal(Alice, 1 ether);
        vm.prank(Alice);

        vm.expectRevert(RoyaltyResolver.DirectPaymentsNotAllowed.selector);
        address(royaltyResolver).call{value: 1 ether}("");
    }

    // helper function creates attestation without any citations
    function createAttestationWithoutCitation(
        address attesterAddress,
        uint256 stakeValue
    ) public returns (bytes32) {
        uint256 initialBalance = 1 ether;
        vm.deal(attesterAddress, initialBalance);
        //empty bytes32 array
        bytes32[] memory citationUIDs = new bytes32[](0);
        AttestationRequest
            memory attestationRequest = generateAttestationRequest({
                attesterAddress: attesterAddress,
                citationUIDs: citationUIDs,
                authorName: bytes32("author"),
                articleTitle: "Example Article",
                articleHash: bytes32("hash"),
                urlOfContent: "http://example.com",
                stakeValue: stakeValue
            });

        vm.prank(attesterAddress);
        bytes32 attestationUID = eas.attest{value: stakeValue}(
            attestationRequest
        );

        // Use the helper function for royalty calculation
        (, , uint256 expectedStakingAmount) = calculateRoyalties(
            stakeValue,
            citationUIDs.length
        );

        // check the balances and staked amounts after the attestation
        uint256 actualStakedAmount = authorStake.getStakedBalance(
            attesterAddress
        );
        assertEq(
            actualStakedAmount,
            expectedStakingAmount,
            "Staking amount calculated incorrectly"
        );
        assertEq(
            attesterAddress.balance,
            (initialBalance - stakeValue),
            "Attester's balance not updated correctly"
        );
        return attestationUID;
    }

    // helper function creates attestation with citations
    function createAttestationWithCitation(
        address attesterAddress,
        bytes32[] memory citationUIDs,
        uint256 stakeValue
    ) public returns (bytes32) {
        uint256 initialAttesterBalance = 1 ether;
        vm.deal(attesterAddress, initialAttesterBalance);

        // Initialize an array to hold initial balances of cited authors
        uint256[] memory initialCitedAuthorBalances = new uint256[](
            citationUIDs.length
        );
        address[] memory citedAuthors = new address[](citationUIDs.length);
        // Fetch the initial balances of the cited authors
        for (uint i = 0; i < citationUIDs.length; i++) {
            // fetch cited author's address using the citation UID
            Attestation memory fetchedAttestation = eas.getAttestation(
                citationUIDs[i]
            );
            address citedAddress = fetchedAttestation.attester;
            citedAuthors[i] = citedAddress;
            initialCitedAuthorBalances[i] = citedAddress.balance;
        }

        AttestationRequest
            memory attestationRequest = generateAttestationRequest({
                attesterAddress: attesterAddress,
                citationUIDs: citationUIDs,
                authorName: bytes32("author"),
                articleTitle: "Example Article",
                articleHash: bytes32("hash"),
                urlOfContent: "http://example.com",
                stakeValue: stakeValue
            });

        assertEq(
            authorStake.getStakedBalance(attesterAddress),
            0,
            "Initial staking amount not 0"
        );

        vm.prank(attesterAddress);
        bytes32 attestationUID = eas.attest{value: stakeValue}(
            attestationRequest
        );

        // Use the helper function for royalty calculation
        (
            ,
            uint256 individualRoyalty,
            uint256 expectedStakingAmount
        ) = calculateRoyalties(stakeValue, citationUIDs.length);

        // check the balances and staked amounts after the attestation
        uint256 actualStakedAmount = authorStake.getStakedBalance(
            attesterAddress
        );

        assertEq(
            actualStakedAmount,
            expectedStakingAmount,
            "Staking amount calculated incorrectly"
        );
        assertEq(
            attesterAddress.balance,
            (initialAttesterBalance - stakeValue),
            "Attester's balance not updated correctly"
        );
        // Check the balances of the cited authors
        for (uint i = 0; i < citationUIDs.length; i++) {
            uint256 initialCitedAuthorBalance = initialCitedAuthorBalances[i];
            uint256 finalCitedAuthorBalance = citedAuthors[i].balance;
            assertEq(
                finalCitedAuthorBalance,
                initialCitedAuthorBalance + individualRoyalty,
                "Cited author's balance not updated correctly"
            );
        }
        return attestationUID;
    }

    // creates multiple attestations without citations
    function testMultipleAttestationsWithoutCitations() public {
        uint256 numberOfAttestations = 5; // Arbitrary number for test
        uint256 stakeValue = 0.5 ether;

        // Create multiple attestations without citations
        for (uint i = 0; i < numberOfAttestations; i++) {
            // generate random attester address: don't use 0 since it will be reverted
            address attesterAddress = address(uint160(i) + 1);
            createAttestationWithoutCitation(attesterAddress, stakeValue);
        }
    }

    // creates multiple attestations with citation
    function testMultipleAttestationsWithCitation() public {
        // Number of attestations to create, with each citing the previous
        uint256 numberOfCitations = 5;
        uint256 stakeValue = 1 ether;

        bytes32[] memory citationUIDs = new bytes32[](1);
        address initialAttester = address(uint160(numberOfCitations + 1)); // Use a unique address
        citationUIDs[0] = createAttestationWithoutCitation(
            initialAttester,
            stakeValue
        );

        // Create subsequent attestations, each citing the previous one
        for (uint i = 0; i < numberOfCitations; i++) {
            // generate random attester address: don't use 0 since it will be reverted
            address attesterAddress = address(uint160(i + 100));
            // Each new attestation cites the last registered attestation
            citationUIDs[0] = createAttestationWithCitation(
                attesterAddress,
                citationUIDs,
                stakeValue
            );
        }
    }

    // creates an attestation with multiple citations
    function testAttestationsWithMultipleCitations() public {
        uint256 numberOfAttestations = 5; // Arbitrary number for test
        uint256 stakeValue = 0.5 ether;
        bytes32[] memory citationUIDs = new bytes32[](numberOfAttestations);

        // Create multiple attestations without citations
        for (uint i = 0; i < numberOfAttestations; i++) {
            // generate random attester address: don't use 0 since it will be reverted
            address attester = address(uint160(i + 200));
            citationUIDs[i] = createAttestationWithoutCitation(
                attester,
                stakeValue
            );
        }
        uint256 stakeValueForMultipleCitations = 1 ether;
        // create attestation with 5 citations
        createAttestationWithCitation(
            Bob,
            citationUIDs,
            stakeValueForMultipleCitations
        );
    }
}
