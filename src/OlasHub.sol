// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IEAS_V027, AttestationRequestData, DelegatedAttestationRequest} from "../src/interfaces/IEAS.sol";
import {Signature} from "eas-contracts/Common.sol";

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
    event ArticlePublished(bytes32 indexed attestationUID, address indexed attester, uint256 stakeAmount);

    mapping(address => Profile) public profiles;
    mapping(address => bytes32[]) public authorArticles;

    uint256 public profileCount;

    IEAS_V027 public EAS_CONTRACT;
    bytes32 public REGISTERED_SCHEMA_UID;

    constructor(address _EAS_ADDRESS, bytes32 _REGISTERED_SCHEMA_UID) {
        EAS_CONTRACT = IEAS_V027(_EAS_ADDRESS);
        REGISTERED_SCHEMA_UID = _REGISTERED_SCHEMA_UID;
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

    function publish(
        Signature memory _signature,
        address _author,
        string memory _title,
        bytes32 _contentUrl,
        bytes32 _mediaUrl,
        uint256 _stakeAmount,
        uint256 _royaltyAmount,
        MarketType _typeOfMarket,
        bytes32[] memory _citationUID
    ) external payable returns (bytes32) {
        //require(hasProfile(_author), "Profile does not exist");
        require(msg.value == _stakeAmount, "Invalid stake amount");
        bytes memory encodedData = abi.encode(
            _author, _title, _contentUrl, _mediaUrl, _stakeAmount, _royaltyAmount, _typeOfMarket, _citationUID
        );

        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: _author,
            expirationTime: 0,
            revocable: false,
            refUID: bytes32(0),
            data: encodedData,
            value: _stakeAmount
        });

        DelegatedAttestationRequest memory delegatedRequest = DelegatedAttestationRequest({
            schema: REGISTERED_SCHEMA_UID,
            data: requestData,
            signature: _signature,
            attester: _author
        });

        // Call the EAS contract
        bytes32 attestationUID = EAS_CONTRACT.attestByDelegation{value: _stakeAmount}(delegatedRequest);
        authorArticles[_author].push(attestationUID);
        emit ArticlePublished(attestationUID, _author, _stakeAmount);
        return attestationUID;
    }
}
