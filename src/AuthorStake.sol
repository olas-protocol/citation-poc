// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title AuthorStake
/// @notice A simple contract for staking Ether.
contract AuthorStake is ReentrancyGuard {
    // Mapping to track staked Ether balances of each address.
    mapping(address => uint256) public stakes;

    event EtherStaked(address indexed from, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);

    function stakeEtherFrom(address staker) public payable nonReentrant {
        require(msg.value > 0, "Must send Ether to stake");
        stakes[staker] += msg.value;
        emit EtherStaked(staker, msg.value);
    }

    // Allows users to withdraw their staked Ether.
    function withdrawStake(uint256 amount) external nonReentrant {
        require(
            stakes[msg.sender] >= amount,
            "Insufficient staked amount to withdraw specified amount"
        );
        require(amount > 0, "Withdrawal amount must be greater than 0");

        stakes[msg.sender] -= amount;
        Address.sendValue(payable(msg.sender), amount); // Safer Ether transfer
        emit EtherWithdrawn(msg.sender, amount);
    }

    // Function to check the staked balance of a caller.
    function getStakedBalance(address staker) external view returns (uint256) {
        return stakes[staker];
    }
}
