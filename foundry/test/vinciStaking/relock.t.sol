// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// RELOCK TESTS ///
// relock postpones checkpoint
// relocking multiple times, but the period-duration is not reduced
// relock reevaluates tier (downgrade)
// relock reevaluates tier (upgrade)
// relock without any stake (or tier) (non existing user)
// make sure staking rewards are not messed up when relocking
// relock when checkpoint can be crossed ??
// view function returns the right current APR rewards
// event is fired

contract TestRelock is BaseTestFunded {
    event Relocked(address indexed user);
    event CheckpointSet(address indexed user, uint256 newCheckpoint);

    function testBasicRelockDowngradingTier() public {
        uint128[] memory thresholds = new uint128[](3);
        thresholds[0] = 10 ether;
        thresholds[1] = 100 ether;
        thresholds[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(thresholds);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(102 ether);
        assertEq(vinciStaking.userTier(user), 2);
        vm.stopPrank();

        // now tiers thresholds are updated, but user tier is not
        vm.prank(operator);
        thresholds[0] = 100 ether;
        thresholds[1] = 1000 ether;
        thresholds[2] = 10000 ether;

        vinciStaking.updateTierThresholds(thresholds);
        assertEq(vinciStaking.userTier(user), 2);

        // now user relocks, and updates tier, getting only tier 1, and postponing checkpoint
        vm.prank(user);
        uint256 timestamp = block.timestamp;
        vinciStaking.relock();

        assertEq(vinciStaking.userTier(user), 1);
        assertGe(vinciStaking.nextCheckpointTimestamp(user), timestamp + 6 * 30 days);
    }

    function testBasicRelockUpgradingTier() public {
        uint128[] memory thresholds = new uint128[](3);
        thresholds[0] = 10 ether;
        thresholds[1] = 100 ether;
        thresholds[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(thresholds);

        vm.startPrank(user);
        vinciToken.mint(user, 10000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(102 ether);
        assertEq(vinciStaking.userTier(user), 2);

        // tier should not change when staking, but when relocking only
        vinciStaking.stake(950 ether);
        assertGt(vinciStaking.activeStaking(user), thresholds[2]);

        assertEq(vinciStaking.userTier(user), 2);
        vinciStaking.relock();
        assertEq(vinciStaking.userTier(user), 3);

        vm.stopPrank();
    }

    function relockMultipleTimesAndCheckpointPeriodIsTheSame() public {
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(2000 ether);
        uint256 tier = vinciStaking.userTier(user);
        assertGt(tier, 0);

        skip(37 days);
        vinciStaking.relock();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);

        skip(13 days);
        vinciStaking.relock();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);

        skip(1 days);
        vinciStaking.relock();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);

        vm.stopPrank();
    }

    function testRelockNonExistingStaker() public {
        vm.prank(nonUser);
        vm.expectRevert(VinciStakingV1.NonExistingStaker.selector);
        vinciStaking.relock();
    }

    function testRelockAndCorrectAPRview() public {
        vm.startPrank(user);
        uint256 stakeAmount = 200 ether;
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(30 days);
        vinciStaking.relock();

        skip(65 days);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeAmount, 95 days));
    }

    function testRelockAndAprRewardsAtEndOfCheckpoint() public {
        vm.startPrank(user);
        uint256 stakeAmount = vinciStaking.getTierThreshold(2) + 10;
        vinciToken.mint(user, stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(37 days);
        vinciStaking.relock();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);

        skip(6 * 30 days + 1);
        assert(vinciStaking.canCrossCheckpoint(user));
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.claimableBalance(user), _estimateRewards(stakeAmount, 6 * 30 days + 37 days));
        vm.stopPrank();
    }

    function testRelockWithCheckpointReadyToBeCrossed() public {
        vm.startPrank(user);
        uint256 stakeAmount = 200 ether;
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(6 * 30 days + 1);
        assert(vinciStaking.canCrossCheckpoint(user));

        // this relock should revert until checkpoint is crossed
        vm.expectRevert(VinciStakingV1.CantRelockBeforeCrossingCheckpoint.selector);
        vinciStaking.relock();

        vinciStaking.crossCheckpoint();
        vinciStaking.relock();
        // as the checkpoint was crossed once, the next staking period is reduced 1 month
        assertApproxEqAbs(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 5 * 30 days, 5);
    }

    function testRelockEventAreFired() public {
        vm.startPrank(user);
        uint256 stakeAmount = 200 ether;
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(30 days);

        vm.expectEmit(true, false, false, true);
        emit CheckpointSet(user, block.timestamp + 6 * 30 days);
        vm.expectEmit(true, false, false, false);
        emit Relocked(user);
        vinciStaking.relock();
    }
}
