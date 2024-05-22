// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract OlasHub {
    struct Profile {
        uint256 profileId;
        string userName;
        address userAddress;
        string userEmail;
        string profileImageUrl;
        uint256 profileCreationTimestamp;
    }

    mapping(address => Profile) public profiles;
    uint256 public profileCount;

    event ProfileCreated(
        uint256 profileId,
        string userName,
        address indexed userAddress,
        string userEmail,
        string profileImageUrl,
        uint256 profileCreationTimestamp
    );

    function createProfile(
        string memory _userName,
        string memory _userEmail,
        string memory _profileImageUrl
    ) public {
        require(
            profiles[msg.sender].userAddress == address(0),
            "Profile already exists"
        );

        profileCount++;
        profiles[msg.sender] = Profile(
            profileCount,
            _userName,
            msg.sender,
            _userEmail,
            _profileImageUrl,
            block.timestamp
        );

        emit ProfileCreated(
            profileCount,
            _userName,
            msg.sender,
            _userEmail,
            _profileImageUrl,
            block.timestamp
        );
    }

    function hasProfile(address user) public view returns (bool) {
        return profiles[user].userAddress != address(0);
    }
}
