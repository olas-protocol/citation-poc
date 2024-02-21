// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {AuthorStake} from "../src/AuthorStake.sol";
import {Vm} from "forge-std/Vm.sol";

contract AuthorStakingContractTest is Test {
    AuthorStake public stakingContract;
    // The attacker contract to test reentrancy attack
    AttackContract public attacker;

    event EtherStaked(address indexed from, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        stakingContract = new AuthorStake();
        attacker = new AttackContract(stakingContract);
    }

    function test_ReentrancyAttack() public {
        vm.deal(address(attacker), 1 ether);

        vm.expectRevert();
        attacker.attack{value: 1 ether}();
    }

    function test_EtherStaking() public {
        address staker = address(1);
        uint256 stakeAmount = 1 ether;

        // Simulate sending Ether to the staking contract
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        // Verify the staked balance is updated
        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            stakeAmount,
            "Staked balance should match the sent amount"
        );
    }

    function test_EtherWithdrawal() public {
        address staker = address(2);
        uint256 stakeAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

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

    function test_WithdrawalExceedsStakedAmount() public {
        address staker = address(3);
        uint256 stakeAmount = 0.5 ether;
        uint256 withdrawAmount = 1 ether; // Attempt to withdraw more than staked

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.startPrank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        // Attempt to withdraw more than the staked amount should fail
        vm.expectRevert(
            "Insufficient staked amount to withdraw specified amount"
        );

        stakingContract.withdrawStake(withdrawAmount);
        vm.stopPrank();
    }

    function test_WithdrawalWithoutStaking() public {
        address staker = address(9);
        uint256 withdrawAmount = 0.5 ether;
        vm.prank(staker);
        vm.expectRevert(
            "Insufficient staked amount to withdraw specified amount"
        );
        stakingContract.withdrawStake(withdrawAmount);
    }

    function test_MultipleStakers() public {
        address staker1 = address(6);
        address staker2 = address(7);
        uint256 stakeAmount1 = 1 ether;
        uint256 stakeAmount2 = 2 ether;

        // Staker 1 stakes
        vm.deal(staker1, stakeAmount1);
        vm.prank(staker1);
        stakingContract.stakeEtherFrom{value: stakeAmount1}(staker1);

        // Staker 2 stakes
        vm.deal(staker2, stakeAmount2);
        vm.prank(staker2);
        stakingContract.stakeEtherFrom{value: stakeAmount2}(staker2);

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

    function test_FullWithdrawalAfterMultipleStakes() public {
        address staker = address(8);
        uint256 firstStakeAmount = 0.5 ether;
        uint256 secondStakeAmount = 0.3 ether;
        uint256 totalStake = firstStakeAmount + secondStakeAmount;

        // First stake
        vm.deal(staker, totalStake);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: firstStakeAmount}(staker);

        // Second stake
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: secondStakeAmount}(staker);

        // Full withdrawal
        vm.prank(staker);
        stakingContract.withdrawStake(totalStake);

        // Verify the balance is zero after withdrawal
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            remainingBalance,
            0,
            "Staker's balance should be zero after full withdrawal"
        );
    }

    function test_DirectEtherTransfer() public {
        uint256 transferAmount = 1 ether;

        (bool success, ) = address(stakingContract).call{value: transferAmount}(
            ""
        );
        // Direct transfer should fail since the contract does not have a receive function
        assertTrue(success == false, "Direct transfer should fail");
    }

    function test_StakingZeroEther() public {
        address staker = address(4);
        uint256 stakeAmount = 0;

        vm.deal(staker, 1 ether); // Ensure staker has some ether to cover gas costs
        vm.prank(staker);

        vm.expectRevert("Must send Ether to stake");
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    }

    function test_StakingAndWithdrawingInLoops() public {
        address staker = address(11);
        uint256 iterations = 5;
        uint256 stakePerIteration = 0.1 ether;
        uint256 totalStake = stakePerIteration * iterations;

        vm.deal(staker, totalStake);
        for (uint256 i = 0; i < iterations; i++) {
            vm.prank(staker);
            stakingContract.stakeEtherFrom{value: stakePerIteration}(staker);
        }

        for (uint256 i = 0; i < iterations; i++) {
            vm.prank(staker);
            stakingContract.withdrawStake(stakePerIteration);
        }

        // Verify the balance is zero after all withdrawals
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            remainingBalance,
            0,
            "Staker's balance should be zero after iterative withdrawals"
        );
    }

    function test_EventEmissionOnStakingAndWithdrawal() public {
        address staker = address(10);
        uint256 stakeAmount = 0.4 ether;
        uint256 withdrawAmount = 0.2 ether;

        vm.recordLogs();
        vm.deal(staker, stakeAmount);
        vm.expectEmit(address(stakingContract));
        vm.startPrank(staker);

        emit EtherStaked(staker, stakeAmount);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        vm.expectEmit(address(stakingContract));
        emit EtherWithdrawn(staker, withdrawAmount);
        stakingContract.withdrawStake(withdrawAmount);

        vm.stopPrank();
    }

    function testFuzz_StakeAndWithdrawAmounts(
        uint256 _stakeAmount,
        uint256 _withdrawAmount
    ) public {
        // Ensure there's a non-zero amount to work with, adjusted to avoid excessively large transactions
        vm.assume(_withdrawAmount > 0);
        vm.assume(_stakeAmount > 0);
        vm.assume(_stakeAmount >= _withdrawAmount);
        address staker = address(1); // random address

        vm.deal(staker, _stakeAmount);
        vm.startPrank(staker);

        stakingContract.stakeEtherFrom{value: _stakeAmount}(staker);
        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            _stakeAmount,
            "Staked amount does not match expected balance"
        );

        stakingContract.withdrawStake(_withdrawAmount);
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            remainingBalance,
            _stakeAmount - _withdrawAmount,
            "Remaining balance should match expected after withdrawal"
        );
        vm.stopPrank();
    }

    function test_StakeEtherForAnotherAddress() public {
        address staker = address(5);
        address beneficiary = address(6);
        uint256 stakeAmount = 1 ether;

        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(beneficiary);

        uint256 stakedBalance = stakingContract.getStakedBalance(beneficiary);
        assertEq(
            stakedBalance,
            stakeAmount,
            "Beneficiary's staked balance should match the sent amount"
        );
    }

    function test_EventEmissionOnStaking() public {
        address staker = address(10);
        uint256 stakeAmount = 0.4 ether;

        // Set up expectations for the event emission
        // The parameters are (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData)
        // In the case of our events, topic1 will be the staker's address, and data will be the stakeAmount
        vm.expectEmit(true, true, false, true);
        emit EtherStaked(staker, stakeAmount);

        // Perform the staking action
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        // The test will fail if the EtherStaked event does not match the expected values
    }

    function test_GasForStaking() public {
        address staker = address(2);
        uint256 stakeAmount = 1 ether;

        vm.deal(staker, stakeAmount);
        vm.startPrank(staker);
        uint256 gasBefore = gasleft();
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        vm.stopPrank();

        console2.log("Gas used for staking 1 ether:", gasUsed);
    }
}

contract AttackContract {
    AuthorStake public target;

    constructor(AuthorStake _target) {
        target = _target;
    }

    // Fallback function used to perform the attack
    fallback() external payable {
        target.withdrawStake(1 ether);
    }

    function attack() external payable {
        target.stakeEtherFrom{value: msg.value}(address(this));
        target.withdrawStake(1 ether);
    }
}
