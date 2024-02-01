// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SchemaResolver} from "eas-contracts/resolver/SchemaResolver.sol";
import {IEAS, Attestation} from "eas-contracts/IEAS.sol";
import {IAuthorStake} from "./interfaces/IAuthorStake.sol";

/// @notice A struct representing the additional custom Olas attestation fields.
struct CustomAttestationSchema {
    bytes32[] citationUID; // An array of citation UIDs
    bytes32 authorName; // The author's name
    string articleTitle; // The title of the article
    bytes32 articleHash; // A hash of the article content
    string urlOfContent; // The URL where the content can be accessed
}

/// @title RoyaltyResolver
/// @notice Distributes royalties among citation attesters and stakes the remaining ether on behalf of the attester.
contract RoyaltyResolver is SchemaResolver, ReentrancyGuard {
    using Address for address payable;

    error InsufficientEthValueSent();
    error InvalidCitationUID();
    error InsufficientIndividualRoyaltyPayment();
    error DirectPaymentsNotAllowed();

    event RoyaltyDistributed(address indexed receiver, uint256 amount);
    event TransferredStake(address indexed stakingContract, uint256 amount);
    event ValueReceived(address indexed attester, uint256 value);

    address private immutable _stakingContract;
    uint256 private constant ROYALTY_PERCENTAGE = 10; // Represents the royalty percentage.

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
    function decodeCustomData(
        bytes memory data
    ) private pure returns (CustomAttestationSchema memory) {
        (
            bytes32[] memory citationUID,
            bytes32 authorName,
            string memory articleTitle,
            bytes32 articleHash,
            string memory urlOfContent
        ) = abi.decode(data, (bytes32[], bytes32, string, bytes32, string));

        return
            CustomAttestationSchema({
                citationUID: citationUID,
                authorName: authorName,
                articleTitle: articleTitle,
                articleHash: articleHash,
                urlOfContent: urlOfContent
            });
    }

    /// @param value = article stake amount
    function onAttest(
        Attestation calldata attestation,
        uint256 value
    ) internal override nonReentrant returns (bool) {
        address attesterAddress = attestation.attester;

        if (value == 0) revert InsufficientEthValueSent();
        emit ValueReceived(attesterAddress, value);

        // Decode the attestation's data field into a struct
        CustomAttestationSchema memory customData = decodeCustomData(
            attestation.data
        );

        uint256 receiversUIDsListLength = customData.citationUID.length;
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

        uint256 stakingAmount = value - totalRoyalty; // Calculate the remaining staking amount after deducting royalty fee and transfer to the staking contract.

        for (uint256 i = 0; i < receiversUIDsListLength; ++i) {
            // Access each citationUID from the decoded data
            bytes32 citationUID = customData.citationUID[i];
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
            royaltyReceiverAddress.sendValue(individualRoyalty); // Using OpenZeppelin's sendValue() for safe Eth transfer.
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

// 1: add Solady safeTransfer
// 2: check for potential integer overflow / underflow issues when calculating the individualRoyalty
// 4: add import specific contract versions
