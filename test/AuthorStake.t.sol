// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {AuthorStakingContract} from "../src/AuthorStake.sol";
import {Vm} from "forge-std/Vm.sol";

contract AuthorStakingContractTest is Test {
    AuthorStakingContract public stakingContract;

    function setUp() public {
        stakingContract = new AuthorStakingContract();
    }

    function testSuccessfulEtherStaking() public {
        address staker = address(1);
        uint256 stakeAmount = 1 ether;

        // Simulate sending Ether to the staking contract
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();

        // Verify the staked balance is updated
        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            stakeAmount,
            "Staked balance should match the sent amount"
        );
    }

    function testSuccessfulEtherWithdrawal() public {
        address staker = address(2);
        uint256 stakeAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();

        // Withdraw part of the staked Ether
        vm.prank(staker);
        stakingContract.withdrawStake(withdrawAmount);

        // Verify the remaining balance
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            remainingBalance,
            stakeAmount - withdrawAmount,
            "Remaining balance should match after withdrawal"
        );
    }

    function testFailWithdrawalExceedsStakedAmount() public {
        address staker = address(3);
        uint256 stakeAmount = 0.5 ether;
        uint256 withdrawAmount = 1 ether; // Attempt to withdraw more than staked

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();

        // Attempt to withdraw more than the staked amount should fail
        vm.prank(staker);
        stakingContract.withdrawStake(withdrawAmount);
        vm.expectRevert(
            "Insufficient staked amount to withdraw specified amount"
        );
    }

    function testMultipleStakers() public {
        address staker1 = address(6);
        address staker2 = address(7);
        uint256 stakeAmount1 = 1 ether;
        uint256 stakeAmount2 = 2 ether;

        // Staker 1 stakes
        vm.deal(staker1, stakeAmount1);
        vm.prank(staker1);
        stakingContract.stakeEther{value: stakeAmount1}();

        // Staker 2 stakes
        vm.deal(staker2, stakeAmount2);
        vm.prank(staker2);
        stakingContract.stakeEther{value: stakeAmount2}();

        // Verify each staker's balance independently
        uint256 stakedBalance1 = stakingContract.getStakedBalance(staker1);
        uint256 stakedBalance2 = stakingContract.getStakedBalance(staker2);
        assertEq(
            stakedBalance1,
            stakeAmount1,
            "Staker 1's staked balance should match"
        );
        assertEq(
            stakedBalance2,
            stakeAmount2,
            "Staker 2's staked balance should match"
        );
    }

    function testDirectEtherReceipt() public {
        address staker = address(5);
        uint256 stakeAmount = 1 ether;

        // Directly transfer Ether to the contract without calling `stakeEther`
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        // Attempt to record the direct transfer as a stake (if applicable)
        // Note: This requires the contract to have a receive() or fallback() function implemented
        (bool success, ) = address(stakingContract).call{value: stakeAmount}(
            ""
        );
        assertTrue(success, "Direct transfer failed");

        // Verify the staked balance (if the contract treats direct transfers as stakes)
        // This step depends on whether your contract logic supports this behavior
        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            stakeAmount,
            "Staked balance should reflect the direct transfer"
        );
    }

    function testWithdrawalOfEntireStakedAmount() public {
        address staker = address(8);
        uint256 stakeAmount = 1 ether;

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();

        // Withdraw the entire staked amount
        vm.prank(staker);
        stakingContract.withdrawStake(stakeAmount);

        // Verify the staked balance is zero
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            remainingBalance,
            0,
            "Staked balance should be zero after full withdrawal"
        );
    }

    function testReStakingAfterWithdrawal() public {
        address staker = address(9);
        uint256 initialStake = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        uint256 secondStake = 0.5 ether;

        vm.deal(staker, initialStake + secondStake);
        vm.prank(staker);
        stakingContract.stakeEther{value: initialStake}();

        vm.prank(staker);
        stakingContract.withdrawStake(withdrawAmount);

        vm.prank(staker);
        stakingContract.stakeEther{value: secondStake}();

        uint256 finalBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            finalBalance,
            1 ether,
            "Final balance should reflect re-staking after withdrawal"
        );
    }

    function testWithdrawalToZeroBalance() public {
        address staker = address(10);
        uint256 stakeAmount = 1 ether;

        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();

        vm.prank(staker);
        stakingContract.withdrawStake(stakeAmount);

        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            0,
            "Staked balance should be zero after withdrawal"
        );
    }

    function testMultipleTransactionsFromSameStaker() public {
        address staker = address(11);
        uint256 firstStake = 0.5 ether;
        uint256 secondStake = 0.3 ether;

        vm.deal(staker, firstStake + secondStake);
        vm.prank(staker);
        stakingContract.stakeEther{value: firstStake}();

        vm.prank(staker);
        stakingContract.stakeEther{value: secondStake}();

        uint256 totalStaked = stakingContract.getStakedBalance(staker);
        assertEq(
            totalStaked,
            firstStake + secondStake,
            "Total staked should sum up all transactions from the same staker"
        );
    }

    function testContractBalanceConsistency() public {
        address staker1 = address(12);
        address staker2 = address(13);
        uint256 stakeAmount1 = 0.5 ether;
        uint256 stakeAmount2 = 0.4 ether;

        vm.deal(staker1, stakeAmount1);
        vm.prank(staker1);
        stakingContract.stakeEther{value: stakeAmount1}();

        vm.deal(staker2, stakeAmount2);
        vm.prank(staker2);
        stakingContract.stakeEther{value: stakeAmount2}();

        uint256 contractBalance = address(stakingContract).balance;
        assertEq(
            contractBalance,
            stakeAmount1 + stakeAmount2,
            "Contract balance should reflect the sum of all stakes"
        );
    }

    function testFailStakingZeroEther() public {
        address staker = address(4);
        uint256 stakeAmount = 0;

        vm.deal(staker, 1 ether); // Ensure staker has some ether to cover gas costs
        vm.prank(staker);
        stakingContract.stakeEther{value: stakeAmount}();
        vm.expectRevert("Must send Ether to stake");
    }
}
