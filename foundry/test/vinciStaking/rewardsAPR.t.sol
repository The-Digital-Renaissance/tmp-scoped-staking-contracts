// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// REWARDS TESTS
// APR update when relocking (moved to relock.t.sol)
// APR calculation for one year, double checking the utility function
// APR rewards for a full checkpoint
// APR rewards (view) after several stakes & unstakes, view, end of period
// APR rewards (after checkpoint) after several stakes & unstakes, view, end of period
// view APR rewards, read function for half a checkpoint period

// APR rewards after several checkpoints crossed
// view APR rewards, read function after several checkpoints crossed
// APR rewards after several checkpoints could have been crosssed, but weren't
// penalization of APRrewards when unstacking
// rewards moved to claimable when crossing checkpoint
// events fired
// rewards handling when there are no funds in the contract ????

contract BaseRewardsTest is BaseTestFunded {
    uint256 amount = 10_000_000 ether;

    function setUp() public override {
        super.setUp();
        vm.startPrank(user);
        vinciToken.mint(user, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vm.stopPrank();
    }
}

contract RewardsTests is BaseRewardsTest {
    event StakingRewardsAllocated(address indexed user, uint256 amount);

    function testUtilityFunctionToEstimateRewards() public {
        // this function does not belong to the contracts, but it has been used in many other tests, so lets make sure it is correct
        uint256 stakeamount = 100 ether;
        uint256 time = 365 days;
        uint256 expectedRewards = 5.5 ether; // 5.5% APR
        assertEq(expectedRewards, _estimateRewards(stakeamount, time));
    }

    function testAPRforViewInMiddleOfPeriod() public {
        skip(99 days);
        uint256 expectedRewards = _estimateRewards(vinciStaking.activeStaking(user), 99 days);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), expectedRewards);
    }

    function testAPREndOfThePeriodBeforeCrossingCheckpoint() public {
        skip(7 * 30 days);
        uint256 stakeamount = vinciStaking.activeStaking(user);

        // rewards only include up to the checkpoint, event though tecnically it has been surpassed
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeamount, 6 * 30 days));
    }

    function testAPRConvertedToClaimableAfterCrossingCheckpoint() public {
        uint256 stakeAmount = vinciStaking.activeStaking(user);

        skip(7 * 30 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.claimableBalance(user), _estimateRewards(stakeAmount, 6 * 30 days));
        // rewards estimated for next checkpoint
        assertApproxEqAbs(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(stakeAmount, 1 * 30 days), 10);
    }

    function testStakeEarnStakeUnstakeAtTheEnd() public {
        uint256 stakeAmount = vinciStaking.activeStaking(user);
        skip(6 * 30 days - 1);
        uint256 accumulatedRewards = vinciStaking.getUnclaimableFromBaseApr(user);
        assertApproxEqAbs(accumulatedRewards, _estimateRewards(stakeAmount, 6 * 30 days - 1), 5);

        // staking and unstaking will remove 50% of the rewards already earned
        vm.startPrank(user);
        vinciStaking.stake(stakeAmount);
        vinciStaking.unstake(stakeAmount);
        vm.stopPrank();
        assertApproxEqAbs(vinciStaking.getUnclaimableFromBaseApr(user), accumulatedRewards / 2, 10);
    }

    function testViewAprRewardsAfterMultipleStakesAndUnstakesAtSameTime() public {
        uint256 amount = 10 ether;
        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vinciStaking.stake(amount);
        vinciStaking.stake(amount);
        vinciStaking.unstake(amount);
        vinciStaking.stake(amount);
        uint256 totalAmount = (3 + 1 - 1) * amount;

        skip(3 * 30 days);
        assertApproxEqAbs(vinciStaking.getUnclaimableFromBaseApr(alice), _estimateRewards(totalAmount, 3 * 30 days), 10);

        skip(3 * 30 days + 1);
        assertApproxEqAbs(vinciStaking.getUnclaimableFromBaseApr(alice), _estimateRewards(totalAmount, 6 * 30 days), 10);

        vinciStaking.crossCheckpoint();
        assertApproxEqAbs(vinciStaking.claimableBalance(alice), _estimateRewards(totalAmount, 6 * 30 days), 10);
    }

    function testAprRewardsFromMultipleStakesAtDifferenTimes() public {
        uint256 amount = 10 ether;
        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 fullduration = 6 * 30 days;
        uint256 startTime = block.timestamp;
        uint256 totalExpectedRewards;

        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration);

        vm.warp(startTime + 15 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 15 days);

        vm.warp(startTime + 30 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 30 days);

        vm.warp(startTime + 90 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 90 days);

        vm.warp(startTime + 6 * 30 days + 1);
        // check the view function
        assertEq(vinciStaking.getUnclaimableFromBaseApr(alice), totalExpectedRewards);
    }

    function testFullPeriodRewardsMultipleStakesAndUnstakes() public {
        uint256 amount = 10 ether;
        uint256 fullduration = 6 * 30 days;
        uint256 fullPeriodRewards;
        uint256 startTime = block.timestamp;

        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vinciStaking.stake(amount);
        fullPeriodRewards += _estimateRewards(amount, fullduration);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), fullPeriodRewards);

        vm.warp(startTime + 15 days);
        vinciStaking.stake(amount);
        fullPeriodRewards += _estimateRewards(amount, fullduration - 15 days);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), fullPeriodRewards);

        vm.warp(startTime + 30 days);
        vinciStaking.stake(amount);
        fullPeriodRewards += _estimateRewards(amount, fullduration - 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), fullPeriodRewards);

        // This penalty is independent of when the unstake is done. Which can lead to unfair situations, but so be it
        vm.warp(startTime + 60 days);
        uint256 unstakeAmount = amount;
        uint256 fullPeriodPenalty = fullPeriodRewards * unstakeAmount / vinciStaking.activeStaking(alice);
        fullPeriodRewards -= fullPeriodPenalty;
        vinciStaking.unstake(unstakeAmount);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), fullPeriodRewards);

        vm.warp(startTime + 90 days);
        vinciStaking.stake(amount);
        fullPeriodRewards += _estimateRewards(amount, fullduration - 90 days);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), fullPeriodRewards);

        vm.warp(startTime + 6 * 30 days + 1);
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.claimableBalance(alice), fullPeriodRewards);
    }

    function testAprRewardsFromMultipleStakesAndUnstakesAtDifferenTimes() public {
        uint256 amount = 10 ether;
        uint256 fullduration = 6 * 30 days;
        uint256 totalExpectedRewards;
        uint256 startTime = block.timestamp;

        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), totalExpectedRewards);

        vm.warp(startTime + 15 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 15 days);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), totalExpectedRewards);

        vm.warp(startTime + 30 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(alice), totalExpectedRewards);

        vm.warp(startTime + 60 days);
        uint256 unstakeAmount = amount;
        uint256 earnedSoFar = _estimateRewards(amount, 15 days) + _estimateRewards(2 * amount, 15 days)
            + _estimateRewards(3 * amount, 30 days);
        assertApproxEqAbs(earnedSoFar, vinciStaking.getTotalUnclaimableBalance(alice), 10);
        uint256 unstakingPenalty = earnedSoFar * unstakeAmount / (3 * amount);
        uint256 staked = vinciStaking.activeStaking(alice);
        totalExpectedRewards -= totalExpectedRewards * unstakeAmount / staked;

        vinciStaking.unstake(unstakeAmount);
        assertApproxEqAbs(vinciStaking.getTotalUnclaimableBalance(alice), earnedSoFar - unstakingPenalty, 10);

        vm.warp(startTime + 90 days);
        vinciStaking.stake(amount);
        totalExpectedRewards += _estimateRewards(amount, fullduration - 90 days);
        vm.warp(startTime + 6 * 30 days + 1);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(alice), totalExpectedRewards);
    }

    function testAprRewardsAfterCrossingMultipleCheckpoints() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        vinciStaking.stake(amount);
        vinciStaking.unstake(amount);

        skip(6.5 * 30 days);
        // check the view function
        assertEq(vinciStaking.getUnclaimableFromBaseApr(alice), _estimateRewards(amount, 6 * 30 days));
    }

    function testStakeAndUpdateRewardsEvent() public {
        uint256 amount = 10 ether;
        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 rewards = _estimateRewards(amount, 6 * 30 days);
        vm.expectEmit(true, false, false, true);
        emit StakingRewardsAllocated(alice, rewards);
        vinciStaking.stake(amount);

        skip(30 days);
        uint256 rewards2 = _estimateRewards(amount, 5 * 30 days);
        vm.expectEmit(true, false, false, true);
        emit StakingRewardsAllocated(alice, rewards2);
        vinciStaking.stake(amount);
    }
}

contract TestRewardsWithNoFunds is BaseTestNotFunded {
    event MissedRewardsAllocation(address indexed user, uint256 entitledPayout, uint256 actualPayout);

    function testMissedRewardsEventFirstStake() public {
        uint256 stakeAmount = 10_000_000 ether;

        vm.startPrank(user);
        vinciToken.mint(user, stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        uint256 reservedRewards = _estimateRewards(stakeAmount, 6 * 30 days);
        vm.expectEmit(true, false, false, true);
        emit MissedRewardsAllocation(user, reservedRewards, 0);
        vinciStaking.stake(stakeAmount);
    }

    function testMissedRewardsEventSecondStake() public {
        uint256 stakeAmount = 10_000_000 ether;

        vm.startPrank(user);
        vinciToken.mint(user, stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vinciStaking.stake(stakeAmount);

        // second event should only contain the missed rewards from second stake (less time)
        skip(40 days);
        uint256 reservedRewards = _estimateRewards(stakeAmount, 6 * 30 days - 40 days);
        vm.expectEmit(true, false, false, true);
        emit MissedRewardsAllocation(user, reservedRewards, 0);
        vinciStaking.stake(stakeAmount);
    }
}
