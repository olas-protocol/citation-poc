// EXAMPLE:  forge test --match-path test/RoyaltyResolver.t.sol -vvvv --fork-url https://eth-sepolia.g.alchemy.com/v2/YOUR API KEY

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {RoyaltyResolver} from "../src/RoyaltyResolver.sol";
import {IEAS, Attestation, AttestationRequestData, AttestationRequest} from "eas-contracts/IEAS.sol";
import {ISchemaRegistry} from "eas-contracts/ISchemaRegistry.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAuthorStake} from "../src/interfaces/IAuthorStake.sol";

contract RoyaltyResolverTest is Test {
    RoyaltyResolver public royaltyResolver;
    IEAS public eas;
    IAuthorStake public authorStake;

    struct CustomAttestationSchema {
        bytes32[] citationUID; // An array of citation UIDs
        bytes32 authorName; // The author's name
        string articleTitle; // The title of the article
        bytes32 articleHash; // A hash of the article content
        string urlOfContent; // The URL where the content can be accessed
    }

    function setUp() public {
        eas = IEAS(0xC2679fBD37d54388Ce493F1DB75320D236e1815e);
        authorStake = IAuthorStake(0x60ab70C38BA5788B6012F4225B75C8abA989d2E9);
        // Deploy a new instance of RoyaltyResolver for testing
        royaltyResolver = RoyaltyResolver(payable(0x5A942EcF94039a660929Da3e18e7cf42f061Ea3f));

        // Basic interaction tests to ensure contracts are correctly initialized
        assertTrue(
            address(eas) != address(0),
            "IEAS address should not be zero"
        );
        assertTrue(
            address(authorStake) != address(0),
            "IAuthorStake address should not be zero"
        );
        assertTrue(
            address(royaltyResolver) != address(0),
            "RoyaltyResolver address should not be zero"
        );
    }

    function testSuccessfulRoyaltyDistributionAndStaking() public {
        // Mock data setup
        address staker = address(1);
        uint256 stakeAmount = 1 ether;
        vm.deal(staker, stakeAmount);
        
        
        bytes32[] memory citationUID = new bytes32[](1); // Example UIDs
        citationUID[
            0
        ] = 0x2c94bedf29576213043764c3f63784c2b075a0180281216c84d879bdc8d24f12;
        bytes32 authorName = bytes32("author");
        string memory articleTitle = "Example Article";
        bytes32 articleHash = bytes32("hash");
        string memory urlOfContent = "http://example.com";
        bytes32 refUID0 = 0x0000000000000000000000000000000000000000000000000000000000000000;
        uint64 timeToExpire = 0;
        bool revoke = false;
        uint256 callValue = 1 ether;

        // Populate citationUIDs and other necessary data
        // CustomAttestationSchema memory customData = CustomAttestationSchema({
        //     // citationUID: citationUIDs,
        //     authorName: bytes32("author"),
        //     articleTitle: "Example Article",
        //     articleHash: bytes32("hash"),
        //     urlOfContent: "http://example.com"
        // });

        bytes memory encodedData = abi.encode(
            citationUID,
            authorName,
            articleTitle,
            articleHash,
            urlOfContent
        );

        console.logBytes(encodedData);

        // Prepare the AttestationRequest
        AttestationRequestData memory requestData = AttestationRequestData({
                recipient: address(1),
                expirationTime: timeToExpire,
                revocable: revoke,
                refUID: refUID0,
                data: encodedData,
                value: callValue
        });

        // Prepare AttestationRequest
        AttestationRequest memory request = AttestationRequest({
            schema: 0x3fe3b953b870a24b213bb11365809709a69699a73db30d7f660fd26ca9218109, // the schema UID
            data: requestData // the AttestationRequestData
        });


        uint256 numOfCitationUID = 1;
        bytes32[] memory citationUID2 = new bytes32[](1); // Example UIDs
        citationUID2[
            0
        ] = 0x2c94bedf29576213043764c3f63784c2b075a0180281216c84d879bdc8d24f12;

        // // Assertions for Royalty Distribution
        for (uint256 i = 0; i < citationUID2.length; ++i) {
            Attestation memory attestation = eas.getAttestation(
                citationUID2[i]
            );
            address citationAuthorAddress = attestation.attester;

        //     // Check the balance increase for each attester (assuming you have a way to check balances)
            uint256 initialCitationAuthorBalance = citationAuthorAddress.balance;

            // Simulate the attestation
        vm.startPrank(address(1));
        bytes32 attestationUID = eas.attest{value: 1 ether}(
            request
        );

        uint256 ROYALTY_PERCENTAGE = 10;
        // Expected royalty calculation
        uint256 totalRoyalty = (callValue * ROYALTY_PERCENTAGE) / 100;
        uint256 individualRoyalty = totalRoyalty / numOfCitationUID;

        // // Expected staking amount
        uint256 expectedStakingAmount = callValue - totalRoyalty;

        // Check the balance increase for each attester (assuming you have a way to check balances)
        uint256 updatedCitationAuthorBalance = citationAuthorAddress.balance;
        uint256 citationAuthorRoyaltyBalance = updatedCitationAuthorBalance - initialCitationAuthorBalance;

        assertEq(
            citationAuthorRoyaltyBalance,
            individualRoyalty,
            "Incorrect royalty distribution"
        );
    }
        
        uint256 ROYALTY_PERCENTAGE2 = 10;
        // Expected royalty calculation
        uint256 totalRoyalty2 = (callValue * ROYALTY_PERCENTAGE2) / 100;
        uint256 expectedStakingAmount2 = callValue - totalRoyalty2;
        

        // Assertions for Staking
        uint256 attesterStakedBalance = authorStake.getStakedBalance(address(1));
        assertEq(
            attesterStakedBalance,
            expectedStakingAmount2,
            "Incorrect staking amount"
        );
    }

    // function testRoyaltyDistributionWithNoCitationAttestations() public {
    //     // Setup test data with no citation UIDs
    //     // ...
    //     // Call the attest function on the eas contract
    //     // ...
    //     // Assert the entire amount is staked
    //     // ...
    // }

    // function testRoyaltyDistributionWithMultipleCitationAttestations() public {
    //     // Setup test data
    //     // ...
    //     // Call the attest function on the eas contract
    //     // ...
    //     // Assert each attester received the correct royalty
    //     // ...
    //     // Assert the remaining amount is staked correctly
    //     // ...
    // }

    // function testRevertingOnZeroValueAttestation() public {
    //     // Setup test data with zero Ether value
    //     // ...

    //     // Assert contract reverts with the correct error
    //     vm.expectRevert(RoyaltyResolver.InsufficientEthValueSent.selector);
    //     // Call the attest function on the eas contract
    //     // ...
    // }

    // function testInvalidCitationUIDHandling() public {
    //     // Setup test data with at least one invalid citation UID
    //     // ...

    //     // Assert contract reverts with the correct error
    //     vm.expectRevert(RoyaltyResolver.InvalidCitationUID.selector);
    //     // Call the attest function on the eas contract
    //     // ...
    // }

    // function testHandlingOfInsufficientIndividualRoyaltyPayment() public {
    //     // Setup test data with small value and multiple citation UIDs
    //     // ...

    //     // Assert contract reverts with the correct error
    //     vm.expectRevert(
    //         RoyaltyResolver.InsufficientIndividualRoyaltyPayment.selector
    //     );
    //     // Call the attest function on the eas contract
    //     // ...
    // }

    // function testIsPayableFunction() public {
    //     bool isPayable = royaltyResolver.isPayable();
    //     assertTrue(isPayable, "isPayable should return true");
    // }

    // function testDirectPaymentReverted() public {
    //     (bool success, ) = address(royaltyResolver).call{value: 1 ether}("");
    //     assertFalse(success, "Direct payment should revert");
    // }
}
