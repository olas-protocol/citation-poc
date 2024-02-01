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
    address attester = address(1);
    bytes32[] private registeredSchemaUIDs;
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

        /*         assertTrue(
            (address(eas) ||
                address(authorStake) ||
                address(royaltyResolver) ||
                address(schemaRegistry)) != address(0),
            "Contracts not deployed or fetched correctly"
        ); */
    }

    function testLogAddresses() public view {
        console.logAddress(address(eas));
        console.logAddress(address(authorStake));
        console.logAddress(address(royaltyResolver));
        console.logAddress(address(schemaRegistry));
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
    function generat
    function createInitialAttestation() public {
        registerSchema();
        vm.deal(attester, 1 ether);

        // attest(AttestationRequest calldata request)
        bytes32[] memory citationUID = new bytes32[](0); // Example UIDs
        bytes32 authorName = bytes32("author");
        bytes32 articleHash = bytes32("hash");
        string memory articleTitle = "Example Article";
        string memory urlOfContent = "http://example.com";
        uint256 stakeValue = 0.5 ether; // Example ETH amount
        uint64 timeToExpire = 0;
        bool revocable = false;
        // encode data
        bytes memory encodedData = abi.encode(
            citationUID,
            authorName,
            articleTitle,
            articleHash,
            urlOfContent
        );

        // Create an instance of AttestationRequestData with hardcoded values
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: attester,
            expirationTime: timeToExpire,
            revocable: revocable,
            refUID: bytes32(0),
            data: encodedData,
            value: stakeValue
        });
        console.log("RegisteredUID Data");
        console.logBytes32(registeredSchemaUIDs[0]);

        bytes32 schemaUID = registeredSchemaUIDs[0];

        vm.prank(attester);
        bytes32 attestationUID = eas.attest{value: stakeValue}(
            AttestationRequest({schema: schemaUID, data: requestData})
        );
    }
}
