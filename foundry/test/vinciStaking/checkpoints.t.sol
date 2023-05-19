// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

contract CheckpointTests is BaseTestFunded {
    event NotifyCannotCrossCheckpointYet(address indexed user);

    function testCrossCheckpointTooSoon() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(3 * 30 days);
        vm.expectRevert(VinciStakingV1.CannotCrossCheckpointYet.selector);
        vinciStaking.crossCheckpoint();
    }

    function testCheckpointDuration() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 rightNow = block.timestamp;
        vinciStaking.stake(stakeAmount);

        uint256 chpDuration = vinciStaking.currentCheckpointDurationInMonths(user);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), rightNow + chpDuration * 30 days);
    }

    function testWhenToCrosscheckpoint() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        uint256 nextCheckpoint = vinciStaking.nextCheckpointTimestamp(user);

        // checkpoint can only be crossed once past the timestamp
        vm.warp(nextCheckpoint);
        vm.expectRevert(VinciStakingV1.CannotCrossCheckpointYet.selector);
        vinciStaking.crossCheckpoint();

        // this should not revert
        vm.warp(nextCheckpoint + 1);
        uint256 unclaimable = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 claimable = vinciStaking.claimableBalance(user);
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.claimableBalance(user), unclaimable + claimable);
    }

    function testOnlyUserOrContractOperatorCanCrossCheckpoint() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(vinciStaking.nextCheckpointTimestamp(user) + 10);
        assert(vinciStaking.canCrossCheckpoint(user));
        assert(vinciStaking.canCrossCheckpoint(alice));

        address[] memory users = new address[](1);

        vm.prank(bob);
        vm.expectRevert();
        users[0] = alice;
        vinciStaking.crossCheckpointTo(users);

        vm.prank(alice);
        vm.expectRevert();
        users[0] = user;
        vinciStaking.crossCheckpointTo(users);

        // This should be fine
        vm.prank(operator);
        users[0] = alice;
        vinciStaking.crossCheckpointTo(users);
        assert(!vinciStaking.canCrossCheckpoint(alice));
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        assert(!vinciStaking.canCrossCheckpoint(user));
    }

    function testBalancesInOneCheckpointCrossing() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        uint256 nextCheckpoint = vinciStaking.nextCheckpointTimestamp(user);
        vm.stopPrank();

        // this should not revert
        vm.warp(nextCheckpoint + 1);

        uint256 unclaimable = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 claimable = vinciStaking.claimableBalance(user);
        uint256 staking = vinciStaking.activeStaking(user);

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vinciStaking.crossCheckpointTo(users);

        assertLt(vinciStaking.getTotalUnclaimableBalance(user), _estimateRewards(staking, 10));
        assertEq(vinciStaking.claimableBalance(user), unclaimable + claimable);
        assertEq(vinciStaking.activeStaking(user), staking);
    }

    function testUpdatedBaseAPRrewardsWhenCrossingCheckpoint() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        uint256 nextCheckpoint = block.timestamp + (6 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), stakeAmount * 6 * 30 days * 550 / (10000 * 365 days));

        // this should not revert
        vm.warp(nextCheckpoint + 1);
        vinciStaking.crossCheckpoint();

        // there should still be some staking amount, and therefore a positive baseAPRrewards at the end of the period
        assertEq(vinciStaking.activeStaking(user), stakeAmount);
        assertEq(vinciStaking.fullPeriodAprRewards(user), stakeAmount * 5 * 30 days * 550 / (10000 * 365 days));
        assertEq(vinciStaking.nextCheckpointTimestamp(user) - block.timestamp, 5 * 30 days - 1);
        // however, the current unclaimable of that baseAPR should have not been unlocked yet, as the cp has just been crossed
        assertLe(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeAmount, 10));
    }

    function testNextCheckpointDateSetCorrectly() public {
        uint256 stakeAmount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        uint256 nextCheckpoint = vinciStaking.nextCheckpointTimestamp(user);
        assertApproxEqAbs(nextCheckpoint, block.timestamp + (6 * 30 days), 1);

        vm.warp(nextCheckpoint + 1);
        vinciStaking.crossCheckpoint();
        assertLe(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeAmount, 2));
    }

    function testNextCheckpointDateSetCorrectlyDelayedCrossing() public {
        uint256 stakeAmount = 100 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        uint256 nextCheckpoint = vinciStaking.nextCheckpointTimestamp(user);
        assertApproxEqAbs(nextCheckpoint, block.timestamp + (6 * 30 days), 1);

        vm.warp(nextCheckpoint + 7 days);
        vinciStaking.crossCheckpoint();
        assertLe(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeAmount, 7 days + 2));
    }

    function testPostponeChekcpointsOneByOne() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 stakeTime = block.timestamp;
        vinciStaking.stake(stakeAmount);

        uint256 expectedCheckpoint1 = stakeTime + (6 * 30 days);
        uint256 expectedCheckpoint2 = expectedCheckpoint1 + (5 * 30 days);
        uint256 expectedCheckpoint3 = expectedCheckpoint2 + (4 * 30 days);
        uint256 expectedCheckpoint4 = expectedCheckpoint3 + (3 * 30 days);
        uint256 expectedCheckpoint5 = expectedCheckpoint4 + (2 * 30 days);
        uint256 expectedCheckpoint6 = expectedCheckpoint5 + (1 * 30 days);
        uint256 expectedCheckpoint7 = expectedCheckpoint6 + (1 * 30 days);
        uint256 expectedCheckpoint8 = expectedCheckpoint7 + (1 * 30 days);

        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint1);
        vm.warp(expectedCheckpoint1 + 5 days);

        // cross checkpoint1
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint2);
        vm.warp(expectedCheckpoint2 + 5 days);

        // cross checkpoint2
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint3);
        vm.warp(expectedCheckpoint3 + 5 days);

        // cross checkpoint3
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint4);
        vm.warp(expectedCheckpoint4 + 5 days);

        // cross checkpoint4
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint5);
        vm.warp(expectedCheckpoint5 + 5 days);

        // cross checkpoint5
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint6);
        vm.warp(expectedCheckpoint6 + 5 days);

        // cross checkpoint6
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint7);
        vm.warp(expectedCheckpoint7 + 5 days);

        // cross checkpoint7
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), expectedCheckpoint8);
        vm.warp(expectedCheckpoint8 + 5 days);
    }

    function testTwoAccumulatedCheckpoints() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 stakeTime = block.timestamp;
        vinciStaking.stake(stakeAmount);

        // lets skip two checkpoints here.
        skip((6 + 5) * 30 days + 5 days);
        assert(vinciStaking.canCrossCheckpoint(user));
        vinciStaking.crossCheckpoint();
        // the next checkpoint should have 3 reductions
        assertEq(vinciStaking.nextCheckpointTimestamp(user), stakeTime + (6 + 5 + 4) * 30 days);
    }

    function testMultipleAccumulatedCheckpoints() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        uint256 firstCheckpoint = vinciStaking.nextCheckpointTimestamp(user);

        // lets skip a lot of checkpoints
        skip((6 + 5 + 4 + 3 + 2 + 23) * 30 days + 5 days);
        assert(vinciStaking.canCrossCheckpoint(user));
        vinciStaking.crossCheckpoint();
        uint256 nextCheckpoint = vinciStaking.nextCheckpointTimestamp(user);

        // the next checkpoint should be in less than 1 month from now
        assertGt(30 days, nextCheckpoint - block.timestamp);
        // also, the date must be a multiple of 30days from the first checkpoint
        assertEq((nextCheckpoint - firstCheckpoint) % 30 days, 0);
    }

    function testRewardsForMultipleAccumulatedCheckpoints() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        // lets skip a lot of checkpoints
        uint256 nmonths = 6 + 5 + 4 + 3 + 2 + 23;
        skip(nmonths * 30 days + 5 days);
        assert(vinciStaking.canCrossCheckpoint(user));
        vinciStaking.crossCheckpoint();

        // APR rewards of missed checkpoints also are part of the new claimable after crossing checkpoint
        assertApproxEqAbs(vinciStaking.claimableBalance(user), _estimateRewards(stakeAmount, nmonths * 30 days), 10);
    }

    function testCrossCheckpointsByOperatorWithNonCapable() public {
        uint256 amount = 100 ether;
        uint256 initTimestamp = block.timestamp;

        vm.startPrank(bob);
        vinciToken.mint(bob, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(10 * amount);
        vm.stopPrank();

        vm.startPrank(alice);
        vinciToken.mint(alice, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(5 * amount);
        vm.stopPrank();

        vm.startPrank(pepe);
        vinciToken.mint(pepe, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(3 * amount);
        vm.stopPrank();

        skip(185 days);
        assert(vinciStaking.canCrossCheckpoint(bob));
        assert(vinciStaking.canCrossCheckpoint(alice));
        assert(vinciStaking.canCrossCheckpoint(pepe));
        assert(!vinciStaking.canCrossCheckpoint(user));

        address[] memory users = new address[](4);
        users[0] = bob;
        users[1] = alice;
        users[2] = pepe;
        users[3] = user;

        vm.prank(operator);
        vinciStaking.crossCheckpointTo(users);

        assert(!vinciStaking.canCrossCheckpoint(bob));
        assert(!vinciStaking.canCrossCheckpoint(alice));
        assert(!vinciStaking.canCrossCheckpoint(pepe));
        assert(!vinciStaking.canCrossCheckpoint(user));

        assertEq(vinciStaking.nextCheckpointTimestamp(bob), initTimestamp + (6 + 5) * 30 days);
        assertEq(vinciStaking.nextCheckpointTimestamp(alice), initTimestamp + (6 + 5) * 30 days);
        assertEq(vinciStaking.nextCheckpointTimestamp(pepe), initTimestamp + (6 + 5) * 30 days);
    }

    function testCrossCheckpointsByOperatorEmitEvent() public {
        uint256 amount = 100 ether;

        vm.startPrank(bob);
        vinciToken.mint(bob, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(10 * amount);
        vm.stopPrank();

        vm.startPrank(alice);
        vinciToken.mint(alice, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(5 * amount);
        vm.stopPrank();

        vm.startPrank(pepe);
        vinciToken.mint(pepe, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(3 * amount);
        vm.stopPrank();

        skip(185 days);

        address[] memory users = new address[](4);
        users[0] = bob;
        users[1] = alice;
        users[2] = pepe;
        users[3] = user;

        vm.startPrank(operator);
        vm.expectEmit(true, false, false, false);
        emit NotifyCannotCrossCheckpointYet(user);
        vinciStaking.crossCheckpointTo(users);
        vm.stopPrank();
    }
}

contract TestCheckpointsWithNoRewardsFunds is BaseTestNotFunded {
    event MissedRewardsAllocation(address indexed user, uint256 entitledPayout, uint256 actualPayout);

    function testCheckpointCrossingWithoutFunds() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 missedPayout = _estimateRewards(stakeAmount, 6 * 30 days);
        assertEq(missedPayout, 2712328767123287671);

        vm.expectEmit(true, false, false, true);
        emit MissedRewardsAllocation(user, missedPayout, 0);
        vinciStaking.stake(stakeAmount);
    }
}
