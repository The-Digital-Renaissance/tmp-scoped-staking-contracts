// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

contract TestEdgeCases is BaseTestNotFunded {
    function testStakeUnstakeSmallAmount() public {
        vm.startPrank(alice);
        vinciToken.mint(alice, 191557948945532507403);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(191557948945532507403);
        vm.stopPrank();

        vm.startPrank(bob);
        vinciToken.mint(bob, 1879);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(1879);

        vinciStaking.unstake(539);
        vm.stopPrank();

        assertEq(vinciStaking.totalVinciStaked(), 191557948945532507403 + 1879 - 539);
        assertEq(vinciStaking.activeStaking(alice), 191557948945532507403);
        assertEq(vinciStaking.activeStaking(bob), 1879 - 539);
        assertEq(vinciStaking.currentlyUnstakingBalance(bob), 539);
    }

    function testStakeUnstakeOneUnit() public {
        vm.startPrank(alice);
        vinciToken.mint(alice, 1);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(1);

        vinciStaking.unstake(1);
        vm.stopPrank();

        assertEq(vinciStaking.totalVinciStaked(), 0);
        assertEq(vinciStaking.activeStaking(alice), 0);
        assertEq(vinciStaking.currentlyUnstakingBalance(alice), 1);
    }

    function testRelockUnderflow() public {
        uint256 amount = 1402;
        vm.startPrank(alice);
        vinciToken.mint(alice, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        vinciStaking.relock();

        vm.stopPrank();
    }

    function testInvariantRewardsPot() public {
        uint256 estimatedUnvestedRewardsPot;

        vm.prank(funder);
        uint256 fundAmount = 9797513434394220756583947056828;
        vinciToken.mint(funder, fundAmount);
        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vm.stopPrank();
        estimatedUnvestedRewardsPot += fundAmount;

        uint256 amount = 621998343960214371043416523537;
        vm.startPrank(alice);
        vinciToken.mint(alice, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vm.stopPrank();

        uint256 totalRewardsFromApr =
            vinciStaking.fullPeriodAprRewards(alice) + vinciStaking.fullPeriodAprRewards(funder);
        uint256 unvestedRewardsPot =
            vinciStaking.vinciStakingRewardsFunds() + vinciStaking.penaltyPot() + totalRewardsFromApr;

        assertApproxEqAbs(unvestedRewardsPot, estimatedUnvestedRewardsPot, 10);
    }

    function testInvariantRewardsPotNoFunds() public {
        uint256 estimatedUnvestedRewardsPot;

        uint256 amount = 621998343960214371043416523537;
        vm.startPrank(alice);
        vinciToken.mint(alice, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vm.stopPrank();

        uint256 totalRewardsFromApr = vinciStaking.fullPeriodAprRewards(alice);
        uint256 unvestedRewardsPot =
            vinciStaking.vinciStakingRewardsFunds() + vinciStaking.penaltyPot() + totalRewardsFromApr;

        assertApproxEqAbs(unvestedRewardsPot, estimatedUnvestedRewardsPot, 10);
    }

    function testRelockUnvestedRewards() public {
        vm.warp(86401);
        vm.warp(172801);

        uint256 amount = 773487949;
        vm.startPrank(alice);
        vinciToken.mint(alice, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vm.stopPrank();

        vm.warp(259201);

        vm.startPrank(funder);
        uint256 fundAmount = 3;
        vinciToken.mint(funder, fundAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vm.stopPrank();

        assertEq(vinciStaking.vinciStakingRewardsFunds(), fundAmount);

        vm.warp(345601);
        vm.warp(432001);
        vm.warp(518401);
        vm.warp(604801);
        vm.warp(691201);

        assert(!vinciStaking.canCrossCheckpoint(alice));
        vm.prank(alice);
        vinciStaking.relock();

        // [rewards inflow] - [rewards outflow] = [contract balance for rewards]
        uint256 totalVested = 0;
        uint256 unvestedRewardsInflow = fundAmount;
        uint256 unvestedRewardsOutflow = totalVested;

        uint256 unvestedRewardsBalance = vinciStaking.vinciStakingRewardsFunds()
            + vinciStaking.fullPeriodAprRewards(alice) + vinciStaking.getUnclaimableFromAirdrops(alice) // this is 0
            + vinciStaking.getUnclaimableFromPenaltyPot(alice) + vinciStaking.penaltyPot();

        assertGe(unvestedRewardsInflow - unvestedRewardsOutflow, unvestedRewardsBalance);
    }
}
