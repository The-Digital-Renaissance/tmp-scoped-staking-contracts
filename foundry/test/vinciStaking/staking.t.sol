// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// STAKING TESTS
// stake fires events
// stakes without approval/balance
// stake increases balance in contract, and decreases it in staker
// stake reduces the stakingrewardsfund
// multiple stakes increase/decrease balances
// multiple stakes, correct APR allocated
// stake increases total staked in contract
// first stake: sets checkpoint
// first stake: sets tier
// second stake: checkpoint unchanged
// second stake: tier unchanged
// second stake for superstaker: penalty pot supply
// stake without funds. revert

contract UserStakingTests is BaseTestFunded {
    event Staked(address indexed user, uint256 amount);
    event MissedRewardsPayout(address indexed user, uint256 entitledPayout, uint256 actualPayout);

    function testStakeWithoutApproval() public {
        assertEq(vinciToken.allowance(user, address(vinciStaking)), 0);
        vm.prank(user);
        vm.expectRevert("ERC20: insufficient allowance");
        vinciStaking.stake(500 ether);
    }

    function testStakeInsufficientBalance() public {
        uint256 userBalance = vinciToken.balanceOf(user);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vinciStaking.stake(userBalance + 1);
        vm.stopPrank();
    }

    function testStakeOverflowBalance() public {
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vm.expectRevert();
        vinciStaking.stake(type(uint256).max - 100);
        vm.stopPrank();
    }

    function testStakingEvent() public {
        vm.startPrank(user);
        uint256 amount = 100 ether;
        vinciToken.approve(address(vinciStaking), 2 * amount);

        vm.expectEmit(true, false, false, true);
        emit Staked(user, amount);
        vinciStaking.stake(amount);

        vm.stopPrank();
    }

    function testStakeAndBalances() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 contractBefore = vinciToken.balanceOf(address(vinciStaking));
        uint256 userBefore = vinciToken.balanceOf(user);

        vinciStaking.stake(amount);
        vinciStaking.stake(amount);

        assertEq(vinciToken.balanceOf(address(vinciStaking)), contractBefore + 2 * amount);
        assertEq(vinciToken.balanceOf(user), userBefore - 2 * amount);
    }

    function testStakeAndRewardsFunds() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 fundsBefore = vinciStaking.vinciStakingRewardsFunds();
        uint256 expectedFullRewards = _estimateRewards(amount, 6 * 30 days);

        vinciStaking.stake(amount);
        vinciStaking.stake(amount);

        assertEq(vinciStaking.vinciStakingRewardsFunds(), fundsBefore - 2 * expectedFullRewards);
    }

    function testStakeAndTotalStaked() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 totalStakedBefore = vinciStaking.totalVinciStaked();

        vinciStaking.stake(amount);
        vinciStaking.stake(amount);

        assertEq(vinciStaking.totalVinciStaked(), totalStakedBefore + 2 * amount);
    }

    function testFirstStakeSetsCheckpoints() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        assertEq(vinciStaking.nextCheckpointTimestamp(user), 0);
        vinciStaking.stake(amount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);
    }

    function testSecondStakeDoesNotChangeCheckpoints() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 stakeTimestamp = block.timestamp;
        vinciStaking.stake(amount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), stakeTimestamp + 6 * 30 days);

        // checkpoint invariant
        vinciStaking.stake(amount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), stakeTimestamp + 6 * 30 days);
    }

    function testFirstStakeSetsTier() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;
        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        uint256 amount = 110 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        assertEq(vinciStaking.userTier(user), 0);
        vinciStaking.stake(amount);
        assertEq(vinciStaking.userTier(user), 2);
    }

    function testSecondStakeDoesNotAlterTier() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;
        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        uint256 amount = 110 ether;
        vm.startPrank(user);
        vinciToken.mint(user, 1000000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        assertEq(vinciStaking.userTier(user), 0);
        vinciStaking.stake(amount);
        assertEq(vinciStaking.userTier(user), 2);
        // tier unchanged after second stake
        vinciStaking.stake(10 * amount);
        assertEq(vinciStaking.userTier(user), 2);
    }

    function testStakeAddsToPpotElegibleSupply() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        skip(7 * 30 days);
        vinciStaking.crossCheckpoint();
        assert(vinciStaking.isSuperstaker(user));

        uint256 ppotSupplyBefore = vinciStaking.getSupplyElegibleForPenaltyPot();
        vinciStaking.stake(amount);
        assertEq(vinciStaking.getSupplyElegibleForPenaltyPot(), ppotSupplyBefore + amount);
    }

    function testStakeAddsToPpotElegibleSupplyTinyDecimals() public {
        uint256 amount = 100_000000000000000123;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        skip(7 * 30 days);
        vinciStaking.crossCheckpoint();
        assert(vinciStaking.isSuperstaker(user));

        uint256 ppotSupplyBefore = vinciStaking.getSupplyElegibleForPenaltyPot();
        vinciStaking.stake(amount);
        assertApproxEqAbs(vinciStaking.getSupplyElegibleForPenaltyPot(), ppotSupplyBefore + amount, 10 ** 6);
    }

    function stakedForbiddenIdCheckpointNotCrossed() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        skip(7 * 30 days);
        assert(vinciStaking.canCrossCheckpoint(user));

        vm.expectRevert(VinciStakingV1.CheckpointHasToBeCrossedFirst.selector);
        vinciStaking.stake(amount);
    }

    function testPotFundsAndRewardsConservation(uint256 time, uint256 unstakeAmount) public {
        _fillPotWithoutDistribution();

        assertEq(vinciStaking.activeStaking(user), 0);
        vm.startPrank(user);
        uint256 amount = 10_000_000 ether;
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        time = bound(time, 1, 6 * 30 days - 1);
        skip(time);
        unstakeAmount = bound(unstakeAmount, 1, amount);

        skip(time);

        uint256 ppotBefore = vinciStaking.penaltyPot();
        uint256 rewardsFundBefore = vinciStaking.vinciStakingRewardsFunds();
        uint256 userFullPerdiodRewardsBefore = vinciStaking.fullPeriodAprRewards(user);
        uint256 userClaimableBefore = vinciStaking.claimableBalance(user);

        if (vinciStaking.canCrossCheckpoint(user)) {
            vinciStaking.crossCheckpoint();
        }

        vinciStaking.unstake(unstakeAmount);

        uint256 ppotAfter = vinciStaking.penaltyPot();
        uint256 rewardsFundAfter = vinciStaking.vinciStakingRewardsFunds();
        uint256 userFullPerdiodRewardsAfter = vinciStaking.fullPeriodAprRewards(user);
        uint256 userClaimableAfter = vinciStaking.claimableBalance(user);

        assertEq(
            ppotBefore + rewardsFundBefore + userFullPerdiodRewardsBefore + userClaimableBefore,
            ppotAfter + rewardsFundAfter + userFullPerdiodRewardsAfter + userClaimableAfter
        );
    }
}

contract StakingTestsNoFunds is BaseTestNotFunded {
    event MissedRewardsPayout(address indexed user, uint256 entitledPayout, uint256 actualPayout);
    event MissedRewardsAllocation(address indexed user, uint256 entitledPayout, uint256 actualPayout);

    function testStakeMissedRewardsAllocation() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 expectedRewards = _estimateRewards(amount, 6 * 30 days);
        vm.expectEmit(true, false, false, true);
        emit MissedRewardsAllocation(user, expectedRewards, 0);
        vinciStaking.stake(amount);
    }

    function testStakeMissedRewardsPayout() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        // 5months checkpoint missed
        skip((6 + 5) * 30 days + 100);
        uint256 expectedRewards = _estimateRewards(amount, 5 * 30 days);

        vm.expectEmit(true, false, false, true);
        emit MissedRewardsPayout(user, expectedRewards, 0);
        vinciStaking.crossCheckpoint();
    }
}
