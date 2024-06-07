// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SchemaResolver} from "eas-contracts/resolver/SchemaResolver.sol";
import {IEAS, Attestation} from "eas-contracts/IEAS.sol";
import {IAuthorStake} from "./interfaces/IAuthorStake.sol";

/// @title RoyaltyResolver
/// @notice Distributes royalties among citation attesters and stakes the remaining ether on behalf of the attester.
contract RoyaltyResolver is SchemaResolver, ReentrancyGuard {
    /// @notice A struct representing the additional custom Olas attestation schema.
    struct OlasArticleSchema {
        address user;
        string title;
        bytes32 contentUrl;
        bytes32 mediaUrl;
        uint256 stakeAmount;
        uint256 royaltyAmount;
        bytes32 typeOfMarket;
        bytes32[] citationUID;
    }

    using Address for address payable;

    // Error definitions
    error InsufficientEthValueSent();
    error InvalidCitationUID();
    error InsufficientIndividualRoyaltyPayment();
    error DirectPaymentsNotAllowed();

    // Event definitions
    event RoyaltyDistributed(address indexed receiver, uint256 amount);
    event TransferredStake(address indexed stakingContract, uint256 amount);
    event ValueReceived(address indexed attester, uint256 value);

    address private immutable _stakingContract;
    uint256 private constant ROYALTY_PERCENTAGE = 10;

    constructor(IEAS eas, address stakingContract) SchemaResolver(eas) {
        require(
            stakingContract != address(0),
            "Invalid staking contract address"
        );
        _stakingContract = stakingContract;
    }

    function isPayable() public pure override returns (bool) {
        return true;
    }

    // Decodes the custom Olas schema data from the standard attestation schema's data field
    function decodeOlasSchema(
        bytes memory data
    ) private pure returns (OlasArticleSchema memory) {
        (
            address user,
            string memory title,
            bytes32 contentUrl,
            bytes32 mediaUrl,
            uint256 stakeAmount,
            uint256 royaltyAmount,
            bytes32 typeOfMarket,
            bytes32[] memory citationUID
        ) = abi.decode(
                data,
                (
                    address,
                    string,
                    bytes32,
                    bytes32,
                    uint256,
                    uint256,
                    bytes32,
                    bytes32[]
                )
            );

        return
            OlasArticleSchema({
                user: user,
                title: title,
                contentUrl: contentUrl,
                mediaUrl: mediaUrl,
                stakeAmount: stakeAmount,
                royaltyAmount: royaltyAmount,
                typeOfMarket: typeOfMarket,
                citationUID: citationUID
            });
    }

    /// @param value The amount of Ether sent with the attestation.
    function onAttest(
        Attestation calldata attestation,
        uint256 value
    ) internal override nonReentrant returns (bool) {
        address attesterAddress = attestation.attester;

        if (value == 0) revert InsufficientEthValueSent();
        emit ValueReceived(attesterAddress, value);

        // Decode the attestation's data field into a struct
        OlasArticleSchema memory olasArticleSchema = decodeOlasSchema(
            attestation.data
        );

        uint256 receiversUIDsListLength = olasArticleSchema.citationUID.length;
        // the attester gets the full stake if there is no citation
        if (receiversUIDsListLength == 0) {
            IAuthorStake(_stakingContract).stakeEtherFrom{value: msg.value}(
                attesterAddress
            );
            emit TransferredStake(_stakingContract, msg.value);
            return true;
        }

        uint256 totalRoyalty = (value * ROYALTY_PERCENTAGE) / 100;
        uint256 individualRoyalty = totalRoyalty / receiversUIDsListLength;
        if (individualRoyalty == 0) {
            revert InsufficientIndividualRoyaltyPayment();
        }
        // Calculate the remaining staking amount after deducting royalty fee and transfer to the staking contract.
        uint256 stakingAmount = value - totalRoyalty;

        for (uint256 i = 0; i < receiversUIDsListLength; ++i) {
            // Access each citationUID from the decoded data
            bytes32 citationUID = olasArticleSchema.citationUID[i];
            // Fetch the attestation for each citationUID
            Attestation memory receiverAttestation = _eas.getAttestation(
                citationUID
            );
            if (address(receiverAttestation.attester) == address(0)) {
                revert InvalidCitationUID();
            }

            address payable royaltyReceiverAddress = payable(
                receiverAttestation.attester
            );
            royaltyReceiverAddress.sendValue(individualRoyalty);
            // Using OpenZeppelin's sendValue() for safe Eth transfer.
            emit RoyaltyDistributed(royaltyReceiverAddress, individualRoyalty);
        }

        IAuthorStake(_stakingContract).stakeEtherFrom{value: stakingAmount}(
            attesterAddress
        );
        emit TransferredStake(_stakingContract, stakingAmount);

        return true;
    }

    function onRevoke(
        Attestation calldata attestation,
        uint256 value
    ) internal override returns (bool) {}

    receive() external payable override {
        revert DirectPaymentsNotAllowed();
    }
}
