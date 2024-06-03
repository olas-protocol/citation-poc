// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AttestationRequestData, DelegatedAttestationRequest, IEAS} from "eas-contracts/IEAS.sol";
import {NO_EXPIRATION_TIME, Signature} from "eas-contracts/Common.sol";

contract OlasHub {
    // Enum definitions
    enum MarketType {
        NewsAndOpinion,
        InvestigativeJournalismAndScientific
    }

    // Strunct definitions
    struct Profile {
        uint256 profileId;
        string userName;
        address userAddress;
        string userEmail;
        string profileImageUrl;
        uint256 profileCreationTimestamp;
    }

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

    // Event definitions
    event ProfileCreated(
        uint256 indexed profileId,
        address indexed userAddress,
        string userName,
        string userEmail,
        string profileImageUrl,
        uint256 profileCreationTimestamp
    );

    mapping(address => Profile) public profiles;
    uint256 public profileCount;

    event AttestationCreated(bytes32 indexed attestationUID, address indexed attester, uint256 stakeAmount);

    IEAS public EAS_CONTRACT;

    constructor(IEAS _EAS_CONTRACT) {
        EAS_CONTRACT = _EAS_CONTRACT;
    }

    function createProfile(string memory _userName, string memory _userEmail, string memory _profileImageUrl)
        external
    {
        require(profiles[msg.sender].userAddress == address(0), "Profile already exists");

        profileCount++;
        profiles[msg.sender] = profiles[msg.sender] = Profile({
            profileId: profileCount,
            userName: _userName,
            userAddress: msg.sender,
            userEmail: _userEmail,
            profileImageUrl: _profileImageUrl,
            profileCreationTimestamp: block.timestamp
        });

        emit ProfileCreated(profileCount, msg.sender, _userName, _userEmail, _profileImageUrl, block.timestamp);
    }

    function hasProfile(address user) public view returns (bool) {
        return profiles[user].userAddress != address(0);
    }
    // Function to create attestation via OlasHub with delegatecall

    function attestArticle(
        Signature memory signature,
        string memory title,
        bytes32 contentUrl,
        bytes32 mediaUrl,
        uint256 stakeAmount,
        uint256 royaltyAmount,
        bytes32[] memory citationUIDs
    ) external payable returns (bytes32) {
        require(hasProfile(msg.sender), "Profile does not exist");

        bytes memory encodedData = abi.encode(title, contentUrl, mediaUrl, stakeAmount, royaltyAmount, citationUIDs);

        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: NO_EXPIRATION_TIME,
            revocable: false,
            refUID: bytes32(0),
            data: encodedData,
            value: stakeAmount
        });

        DelegatedAttestationRequest memory delegatedRequest = DelegatedAttestationRequest({
            schema: bytes32(0),
            data: requestData,
            signature: signature,
            attester: msg.sender,
            deadline: NO_EXPIRATION_TIME
        });

        // Call the EAS contract
        bytes32 attestationUID = EAS_CONTRACT.attestByDelegation{value: stakeAmount}(delegatedRequest);
        emit AttestationCreated(attestationUID, msg.sender, stakeAmount);
        return attestationUID;
    }
}
