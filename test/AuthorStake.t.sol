// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {AuthorStake} from "../src/AuthorStake.sol";
import {Vm} from "forge-std/Vm.sol";

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

contract AuthorStakingContractTest is Test {
    AuthorStake public stakingContract;
    AttackContract public attacker;

    event EtherStaked(address indexed from, uint256 amount);
    event EtherWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        stakingContract = new AuthorStake();
        attacker = new AttackContract(stakingContract);
    }

    function testReentrancyAttack() public {
        vm.deal(address(attacker), 1 ether);
        
        vm.expectRevert();
        attacker.attack{value: 1 ether}();
    }

    function testSuccessfulEtherStaking() public {
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

    function testSuccessfulEtherWithdrawal() public {
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

    function testFailWithdrawalExceedsStakedAmount() public {
        address staker = address(3);
        uint256 stakeAmount = 0.5 ether;
        uint256 withdrawAmount = 1 ether; // Attempt to withdraw more than staked

        // Setup: Stake Ether
        vm.deal(staker, stakeAmount);
        vm.startPrank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        // Attempt to withdraw more than the staked amount should fail
        vm.expectRevert(bytes(""));

        stakingContract.withdrawStake(withdrawAmount);
        vm.stopPrank();
    }

    function testFailWithdrawalWithoutStaking() public {
        address staker = address(9);
        uint256 withdrawAmount = 0.1 ether;

        vm.prank(staker);
        vm.expectRevert(bytes(""));
        stakingContract.withdrawStake(withdrawAmount);
    }

    function testMultipleStakers() public {
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

    function testFullWithdrawalAfterMultipleStakes() public {
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

    function testFailDirectEtherTransfer() public {
        uint256 transferAmount = 1 ether;

        // Expect revert on direct transfer (if applicable)
        vm.expectRevert(bytes(""));
        (bool success, ) = address(stakingContract).call{value: transferAmount}(
            ""
        );

        assertTrue(!success, "Direct transfer should fail");
    }

    function testFailStakingZeroEther() public {
        address staker = address(4);
        uint256 stakeAmount = 0;

        vm.deal(staker, 1 ether); // Ensure staker has some ether to cover gas costs
        vm.prank(staker);

        vm.expectRevert(bytes(""));
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    }

    function testStakingAndWithdrawingInLoops() public {
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

    function testEventEmissionOnStakingAndWithdrawal() public {
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

    function testFuzzStakeEther(uint256 _amount) public {
        // Skip the test case if the fuzzed amount is 0 to avoid failing the "Must send Ether to stake" requirement
        if (_amount == 0) return;

        // Ensure the staker has enough Ether to cover the stake.
        uint256 stakeAmount = _amount % 10 ether; // Example to limit the stake amount for practical testing

        address staker = address(this);
        vm.deal(staker, stakeAmount + 1 ether); // Ensure the staker has more than the stake amount
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);

        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(
            stakedBalance,
            stakeAmount,
            "Staked amount does not match expected balance"
        );
    }

    function testFuzzWithdrawalAmounts(uint256 _withdrawAmount) public {
        // Ensure there's a non-zero amount to work with, adjusted to avoid excessively large transactions
        uint256 withdrawAmount = (_withdrawAmount % 1 ether) + 1; // Ensure at least 1 wei is withdrawn and cap at 1 ether for practicality
    
        address staker = address(this);
        // Stake an amount slightly larger than the maximum withdrawal amount to ensure coverage
        uint256 stakeAmount = withdrawAmount + 1; // Ensure stake is sufficient
    
        vm.deal(staker, stakeAmount);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    
        vm.prank(staker);
        stakingContract.withdrawStake(withdrawAmount);
    
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(remainingBalance, stakeAmount - withdrawAmount, "Remaining balance should match expected after withdrawal");
    }
    

    function testStakeEtherForAnotherAddress() public {
        address staker = address(5);
        address beneficiary = address(6);
        uint256 stakeAmount = 1 ether;
    
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(beneficiary);
    
        uint256 stakedBalance = stakingContract.getStakedBalance(beneficiary);
        assertEq(stakedBalance, stakeAmount, "Beneficiary's staked balance should match the sent amount");
    }

    function testExactWithdrawal() public {
        address staker = address(7);
        uint256 stakeAmount = 1 ether;
    
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    
        vm.prank(staker);
        stakingContract.withdrawStake(stakeAmount);
    
        uint256 remainingBalance = stakingContract.getStakedBalance(staker);
        assertEq(remainingBalance, 0, "Remaining balance should be zero after exact withdrawal");
    }    
    
    function testEventEmissionOnStaking() public {
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

    function testMinimalEtherStake() public {
        address staker = address(1);
        uint256 stakeAmount = 1 wei;
    
        vm.deal(staker, stakeAmount);
        vm.prank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    
        uint256 stakedBalance = stakingContract.getStakedBalance(staker);
        assertEq(stakedBalance, stakeAmount, "Staked balance should match the minimal stake amount");
    }
    
    function testGasForStaking() public {
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
    
    function testWithdrawalExceedsStakedAmountWithRevertReason() public {
        address staker = address(3);
        uint256 stakeAmount = 0.5 ether;
        uint256 withdrawAmount = 1 ether; // Attempt to withdraw more than staked
    
        vm.deal(staker, stakeAmount);
        vm.startPrank(staker);
        stakingContract.stakeEtherFrom{value: stakeAmount}(staker);
    
        vm.expectRevert("Insufficient staked amount to withdraw specified amount");
        stakingContract.withdrawStake(withdrawAmount);
        vm.stopPrank();
    }

    receive() external payable {}
}
