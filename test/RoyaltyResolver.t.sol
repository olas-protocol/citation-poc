// EXAMPLE:  forge test --match-path test/RoyaltyResolver.t.sol -vvvv --fork-url $SEPOLIA_RPC_URL

/*
1- Deploy EAS contract
2- Deploy AuthorStake contract
3- Deploy RoyaltyResolver contract
4- Register schema on EAS contract with using Royalty Resolver Contract
5- Create attestation request on EAS contract
*/
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
    address attester1 = address(1);
    address attester2 = address(2);
    bytes32[] private registeredSchemaUIDs;
    bytes32[] private registeredAttestationUIDs;
    uint256 ROYALTY_PERCENTAGE = 10;

    struct CustomAttestationSchema {
        bytes32[] citationUID; // An array of citation UIDs
        bytes32 authorName; // The author's name
        string articleTitle; // The title of the article
        bytes32 articleHash; // A hash of the article content
        string urlOfContent; // The URL where the content can be accessed
    }

    function setUp() public {
        // deploy contracts
        eas = EAS(0xC2679fBD37d54388Ce493F1DB75320D236e1815e);
        authorStake = new AuthorStake();
        royaltyResolver = new RoyaltyResolver(eas, address(authorStake));
        schemaRegistry = eas.getSchemaRegistry();
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
        //register(string schema,address resolver,bool revocable)
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
        uint256 expectedStakingAmount = stakeValue - totalRoyalty;
        return (totalRoyalty, individualRoyalty, expectedStakingAmount);
    }

    function testCreateInitialAttestation() public {
        registerSchema();
        address attesterAddress = attester1;

        uint256 initialBalance = 1 ether;
        uint256 stakeValue = 0.5 ether;

        vm.deal(attester1, initialBalance);
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
        registeredAttestationUIDs.push(attestationUID);

        // Use the helper function for royalty calculation
        (
            uint256 totalRoyalty,
            uint256 individualRoyalty,
            uint256 expectedStakingAmount
        ) = calculateRoyalties(stakeValue, citationUIDs.length);

        assertEq(
            authorStake.getStakedBalance(attesterAddress),
            expectedStakingAmount,
            "Staking amount calculated incorrectly"
        );
        assertEq(
            attesterAddress.balance,
            (initialBalance - stakeValue),
            "Attester's balance not updated correctly"
        );
    }

    function testCreateAttestationWithCitation() public {
        // attester 2 cites attester 1
        address attesterAddress = attester2;
        testCreateInitialAttestation();
        uint256 initialBalance = 1 ether;

        vm.deal(attesterAddress, initialBalance);
        uint256 stakeValue = 1 ether;

        bytes32[] memory citationUIDs = new bytes32[](1);
        Attestation memory fetchedAttestation = eas.getAttestation(
            registeredAttestationUIDs[0]
        );
        address citedAddress = fetchedAttestation.attester;
        uint256 initialCitedAuthorBalance = citedAddress.balance;
        // citing the first author by giving his attestation UID
        citationUIDs[0] = registeredAttestationUIDs[0];
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
            uint256 totalRoyalty,
            uint256 individualRoyalty,
            uint256 expectedStakingAmount
        ) = calculateRoyalties(stakeValue, citationUIDs.length);

        assertEq(
            authorStake.getStakedBalance(attesterAddress),
            expectedStakingAmount,
            "Staking amount calculated incorrectly"
        );
        assertEq(
            attesterAddress.balance,
            (initialBalance - stakeValue),
            "Cited author's balance not updated correctly"
        );
        assertEq(
            citedAddress.balance,
            initialCitedAuthorBalance + individualRoyalty,
            "Cited author's balance not updated correctly"
        );
    }

    function testMultipleAttestationsWithoutCitations() public {
        uint256 numberOfAttestations = 10; // Arbitrary number for test
        uint256 initialBalance = 10 ether;
        uint256 stakeValue = 0.5 ether;

        // Pre-fund attesters and register schema
        for (uint i = 1; i <= numberOfAttestations; i++) {
            address attesterAddress = address(uint160(i)); // Convert i to a valid Ethereum address
            vm.deal(attesterAddress, initialBalance);
        }

        registerSchema();

        // Create multiple attestations without citations
        for (uint i = 1; i <= numberOfAttestations; i++) {
            address attesterAddress = address(uint160(i));
            bytes32[] memory citationUIDs = new bytes32[](0); // No citations
            AttestationRequest
                memory attestationRequest = generateAttestationRequest({
                    attesterAddress: attesterAddress,
                    citationUIDs: citationUIDs,
                    authorName: bytes32("author"),
                    articleTitle: "Article Title",
                    articleHash: bytes32("articleHash"),
                    urlOfContent: "http://example.com",
                    stakeValue: stakeValue
                });

            // Simulate attestation creation
            vm.prank(attesterAddress);
            eas.attest{value: stakeValue}(attestationRequest);
        }

        // Verify balance and staked amount for each attester
        for (uint i = 1; i <= numberOfAttestations; i++) {
            address attesterAddress = address(uint160(i));
            uint256 expectedBalance = initialBalance - stakeValue;
            uint256 actualBalance = attesterAddress.balance;
            assertEq(
                actualBalance,
                expectedBalance,
                "Incorrect balance after attestation"
            );

            uint256 expectedStakedAmount = stakeValue;
            uint256 actualStakedAmount = authorStake.getStakedBalance(
                attesterAddress
            );
            assertEq(
                actualStakedAmount,
                expectedStakedAmount,
                "Incorrect staked amount"
            );
        }
    }

    function testMultipleAttestationsWithCitations() public {
        uint256 numberOfCitations = 5; // Number of attestations to create, with each citing the previous
        uint256 initialBalance = 10 ether;
        uint256 stakeValue = 1 ether;
        uint256 citedStakeValue = 0.5 ether; // Stake value for cited attestations

        // Register schema once for all attestations
        registerSchema();

        // Pre-fund the first attester and create the initial attestation
        address initialAttester = address(uint160(numberOfCitations + 1)); // Use a unique address for the initial attester
        vm.deal(initialAttester, initialBalance);
        bytes32[] memory initialCitationUIDs = new bytes32[](0); // No citations for the first attestation

        AttestationRequest
            memory initialAttestationRequest = generateAttestationRequest({
                attesterAddress: initialAttester,
                citationUIDs: initialCitationUIDs,
                authorName: bytes32("initialAuthor"),
                articleTitle: "Initial Article",
                articleHash: bytes32("initialHash"),
                urlOfContent: "http://initial.com",
                stakeValue: citedStakeValue
            });

        vm.prank(initialAttester);
        bytes32 initialAttestationUID = eas.attest{value: citedStakeValue}(
            initialAttestationRequest
        );
        registeredAttestationUIDs.push(initialAttestationUID);

        // Create subsequent attestations, each citing the previous one
        for (uint i = 1; i <= numberOfCitations; i++) {
            address attesterAddress = address(uint160(i)); // Unique address for each attester
            vm.deal(attesterAddress, initialBalance);

            // Each new attestation cites the one before it
            bytes32[] memory citationUIDs = new bytes32[](1);
            citationUIDs[0] = registeredAttestationUIDs[
                registeredAttestationUIDs.length - 1
            ]; // Cite the last registered attestation

            AttestationRequest
                memory attestationRequest = generateAttestationRequest({
                    attesterAddress: attesterAddress,
                    citationUIDs: citationUIDs,
                    authorName: bytes32("author"),
                    articleTitle: "Cited Article",
                    articleHash: bytes32("hash"),
                    urlOfContent: "http://example.com",
                    stakeValue: stakeValue
                });
            address citedAuthor = eas.getAttestation(citationUIDs[0]).attester;
            uint256 initialCitedAuthorBalance = citedAuthor.balance;

            vm.prank(attesterAddress);
            bytes32 attestationUID = eas.attest{value: stakeValue}(
                attestationRequest
            );
            registeredAttestationUIDs.push(attestationUID);

            // Use the helper function for royalty calculation
            (
                uint256 totalRoyalty,
                uint256 individualRoyalty,
                uint256 expectedStakingAmount
            ) = calculateRoyalties(stakeValue, 1);

            // Check balances and staked amounts after each attestation
            uint256 expectedAttesterBalance = initialBalance - stakeValue;
            uint256 actualAttesterBalance = attesterAddress.balance;
            assertEq(
                actualAttesterBalance,
                expectedAttesterBalance,
                "Incorrect attester balance after attestation"
            );

            uint256 actualStakedAmount = authorStake.getStakedBalance(
                attesterAddress
            );
            assertEq(
                actualStakedAmount,
                expectedStakingAmount,
                "Incorrect staked amount after attestation"
            );

            // Verify the cited author's balance is updated with the royalty
            uint256 expectedCitedAuthorBalance = initialCitedAuthorBalance +
                individualRoyalty;
            uint256 actualCitedAuthorBalance = citedAuthor.balance; // Assuming you can access balance directly or via a mock
            assertEq(
                actualCitedAuthorBalance,
                expectedCitedAuthorBalance,
                "Incorrect cited author balance after royalty distribution"
            );
        }
    }
}
