// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// UNSTAKING TESTS ///
// token balance constant in the contract and user
// unstakingBalance increased, and active staking decreased, and totalStaked
// reelase time set correctly
// airdrops rewards reduced correctly
// superstaker kept if partial unstaking
// tiers reevaluation when unstaking (downgrade)
// tiers reevaluation when unstaking (not upgrade)
// withdrawal not allowed release time not passed
// double unstake delays the release time
// double unstake increases unstake amount
// double unstake reduces rewards twice
// conservation of balances when unstaking. Decimals lost between balances adjustments
// unstake more than staking balance
// multiple unstakes reduce rewards similarly
// fuzzy: APR rewards at the end of the period properly calculated: different amount and differnt times
// fuzzy: airdrop rewards reduced (different unstake amounts)
// fuzzy: penaltypot rewards, different unstake amounts
// totalRewards reduced when filled from three sources

contract BaseUnstake is BaseTestFunded {
    uint256 stakeAmount = 900_000 ether;

    function setUp() public override {
        super.setUp();
        vm.startPrank(user);
        vinciToken.mint(user, stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();
    }
}

contract UnstakingTests is BaseUnstake {
    event UnstakingInitiated(address indexed user, uint256 amount);

    function testUnstakeAndTokenBalances() public {
        uint256 unstakeAmount = stakeAmount / 2;
        uint256 initialBalance = vinciToken.balanceOf(user);
        uint256 initialStakingBalance = vinciToken.balanceOf(address(vinciStaking));

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciToken.balanceOf(user), initialBalance);
        assertEq(vinciToken.balanceOf(address(vinciStaking)), initialStakingBalance);
    }

    function testUnstakeAndInternalBalances() public {
        uint256 unstakeAmount = stakeAmount / 2;
        uint256 initialActiveStaking = vinciStaking.activeStaking(user);
        uint256 intitalUnstakingBalance = vinciStaking.currentlyUnstakingBalance(user);
        uint256 initialTotalStaked = vinciStaking.totalVinciStaked();

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciStaking.activeStaking(user), initialActiveStaking - unstakeAmount);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), intitalUnstakingBalance + unstakeAmount);
        assertEq(vinciStaking.totalVinciStaked(), initialTotalStaked - unstakeAmount);
    }

    function testUnstakeAndReleaseTimeSet() public {
        uint256 unstakeAmount = stakeAmount / 2;
        assertEq(vinciStaking.unstakingReleaseTime(user), 0);

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciStaking.unstakingReleaseTime(user), block.timestamp + 14 days);
    }

    function testUnstakeRecalculateAprRewardsPartialUnstake() public {
        skip(70 days);

        uint256 fullperiodRewards = vinciStaking.fullPeriodAprRewards(user);
        uint256 earnedAprRewards = vinciStaking.getUnclaimableFromBaseApr(user);
        uint256 fundsBefore = vinciStaking.vinciStakingRewardsFunds();
        uint256 ppotBefore = vinciStaking.penaltyPot();
        assertGt(fullperiodRewards, 0);
        assertGt(earnedAprRewards, 0);

        vm.startPrank(user);
        vinciStaking.unstake(stakeAmount / 7);
        uint256 estimatedPenalty = _estimateRewards(stakeAmount / 7, 70 days);

        assertEq(vinciStaking.penaltyPot(), ppotBefore + estimatedPenalty);
        assertEq(vinciStaking.vinciStakingRewardsFunds(), fundsBefore + fullperiodRewards / 7 - estimatedPenalty);
        assertEq(vinciStaking.fullPeriodAprRewards(user), fullperiodRewards - (fullperiodRewards / 7));
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), earnedAprRewards - (earnedAprRewards / 7));
    }

    function testUnstakeRecalculateAprRewardsFullUnstake() public {
        skip(50 days);

        assertGt(vinciStaking.getUnclaimableFromBaseApr(user), 0);

        vm.prank(user);
        vinciStaking.unstake(stakeAmount);
        // full unstake should remove all rewards
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), 0);
    }

    function testUnstakeAndAprRewardsReducedSimple() public {
        uint256 unstakeAmount = stakeAmount / 9;
        skip(57 days);

        uint256 fullperiodRewards = vinciStaking.fullPeriodAprRewards(user);
        uint256 earnedAprRewards = vinciStaking.getUnclaimableFromBaseApr(user);

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);

        // unstake / stake == (fullperiodRewards - vinciStaking.fullperiodRewards()) / fullperiodRewards
        // unstake * fullperiodRewards == stake * (fullperiodRewards - vinciStaking.fullperiodRewards())
        assertApproxEqRel(
            unstakeAmount * fullperiodRewards,
            stakeAmount * (fullperiodRewards - vinciStaking.fullPeriodAprRewards(user)),
            1e6
        );
        assertApproxEqRel(
            unstakeAmount * earnedAprRewards,
            stakeAmount * (earnedAprRewards - vinciStaking.getUnclaimableFromBaseApr(user)),
            1e6
        );
    }

    function testUnstakeAndAprRewardsReducedFuzzy(uint256 time, uint256 unstakeAmount) public {
        uint256 staked = vinciStaking.activeStaking(user);
        time = bound(time, 10000, 6 * 30 days);
        unstakeAmount = bound(unstakeAmount, 1000, staked);

        skip(time);

        uint256 fullperiodRewards = vinciStaking.fullPeriodAprRewards(user);
        uint256 earnedAprRewards = vinciStaking.getUnclaimableFromBaseApr(user);

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);

        // fullPeriodPenalty / fullperiodRewards = unstakeAmount / staked
        // fullPeriodPenalty = fullperiodRewards * unstakeAmount / staked
        uint256 fullPeriodPenalty = fullperiodRewards - vinciStaking.fullPeriodAprRewards(user);
        assertApproxEqAbs(fullPeriodPenalty, fullperiodRewards * unstakeAmount / staked, 10);

        // earnedRewardsPenalty = earnedAprRewards - newEarnedAprRewards
        // earnedRewardsPenalty / earnedAprRewards = unstakeAmount / staked
        // earnedRewardsPenalty = earnedAprRewards * unstakeAmount / staked
        uint256 newEarnedAprRewards = vinciStaking.getUnclaimableFromBaseApr(user);
        // Here it is formulated weirdly to avoid underflow of subtracting earnedAprRewards - newEarnedAprRewards (rounding errors)
        assertApproxEqAbs(earnedAprRewards, newEarnedAprRewards + earnedAprRewards * unstakeAmount / staked, 10);
    }

    function testRewardsReductionVsFullPeriodReduction(uint256 time, uint256 unstakeAmount) public {
        uint256 staked = vinciStaking.activeStaking(user);
        time = bound(time, 10, 6 * 30 days);
        unstakeAmount = bound(unstakeAmount, 1, staked);

        skip(time);

        console.log("vinciStaking.activeStaking(user)", staked);
        uint256 fullperiodRewards = vinciStaking.fullPeriodAprRewards(user);
        uint256 earnedAprRewards = vinciStaking.getUnclaimableFromBaseApr(user);

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);

        uint256 fullperiodRewardsNew = vinciStaking.fullPeriodAprRewards(user);
        uint256 earnedAprRewardsNew = vinciStaking.getUnclaimableFromBaseApr(user);

        uint256 fullPeriodDiff = fullperiodRewards - fullperiodRewardsNew;

        // this difference can underflow, so we check first that the underflow would only be by 1 unit
        uint256 ALLOWED_ERROR = 1;
        assertGe(earnedAprRewards + ALLOWED_ERROR, earnedAprRewardsNew);
        uint256 earnedAprDiff = earnedAprRewards > earnedAprRewardsNew
            ? earnedAprRewards - earnedAprRewardsNew
            : earnedAprRewardsNew - earnedAprRewards;

        assertApproxEqAbs(fullPeriodDiff, fullperiodRewards * unstakeAmount / staked, 10);
        assertApproxEqAbs(earnedAprDiff, earnedAprRewards * unstakeAmount / staked, 10);
    }

    function testUnstakeAirdropReductionFuzzy(uint256 unstakeAmount) public {
        uint256 staked = vinciStaking.activeStaking(user);
        unstakeAmount = bound(unstakeAmount, 1, staked);

        uint256 airdropped = 1_000_000 ether;
        _airdrop(user, airdropped);

        uint256 rewardsFromAirdrop = vinciStaking.getUnclaimableFromAirdrops(user);
        uint256 totalRewards = vinciStaking.getTotalUnclaimableBalance(user);
        assertEq(rewardsFromAirdrop, airdropped);

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        // airdropPenalty / airdropped = unstaked / staked
        // airdropPenalty = airdropped * unstaked / staked
        uint256 airdropPenalty = rewardsFromAirdrop - vinciStaking.getUnclaimableFromAirdrops(user);
        assertApproxEqAbs(airdropPenalty, airdropped * unstakeAmount / staked, 10);

        // totalPenalty / unclaimable = unstaked / staked
        // totalPenalty = unclaimable * unstaked / staked
        uint256 totalPenalty = totalRewards - vinciStaking.getTotalUnclaimableBalance(user);
        assertApproxEqAbs(totalPenalty, totalRewards * unstakeAmount / staked, 10);
    }

    function testSuperStakerMaintainedIfPartialUnstake() public {
        skip(7 * 30 days);

        vm.startPrank(user);
        vinciStaking.crossCheckpoint();
        assert(vinciStaking.isSuperstaker(user));

        uint256 unstakeAmount = stakeAmount / 2;
        vinciStaking.unstake(unstakeAmount);
        assert(vinciStaking.isSuperstaker(user));

        // but looses it if fully unstaked
        vinciStaking.unstake(vinciStaking.activeStaking(user));
        assert(!vinciStaking.isSuperstaker(user));
        vm.stopPrank();
    }

    function testUnstakeDowngradeTier() public {
        uint256 tier3 = vinciStaking.getTierThreshold(3);
        uint256 stakeAmount = tier3 + 10;

        assertEq(vinciStaking.userTier(alice), 0);
        assertEq(vinciStaking.calculateTier(stakeAmount), 3);

        vm.startPrank(alice);
        vinciToken.mint(alice, stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        assertEq(vinciStaking.userTier(alice), 3);

        // this should be enough to downgrade tier
        uint256 unstakeAmount = 20;
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciStaking.userTier(alice), 2);

        vm.stopPrank();
    }

    function testUnstakeNotUpgradeTier() public {
        uint128[] memory tiers = new uint128[](4);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;
        tiers[3] = 10000 ether;
        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        uint256 amount = 1050 ether;
        vm.startPrank(alice);
        vinciToken.mint(alice, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        assertEq(vinciStaking.userTier(alice), 3);
        vm.stopPrank();

        uint128[] memory newTiers = new uint128[](4);
        newTiers[0] = 1 ether;
        newTiers[1] = 10 ether;
        newTiers[2] = 100 ether;
        newTiers[3] = 1000 ether;
        vm.prank(operator);
        vinciStaking.updateTierThresholds(newTiers);

        // unstaking 20, she would still be above the new tire3 threshold, but she should keep tier 2
        vm.prank(alice);
        uint256 unstakeAmount = 20;
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciStaking.userTier(alice), 3);
    }

    function testUnstakeWithdrawNotAllowedUntilReleased() public {
        uint256 unstakeAmount = stakeAmount / 3;
        assertEq(vinciStaking.unstakingReleaseTime(user), 0);

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);
        uint256 releaseTime = block.timestamp + 14 days;

        assertEq(vinciStaking.unstakingReleaseTime(user), releaseTime);

        skip(10 days);
        vm.expectRevert(VinciStakingV1.UnstakedAmountNotReleasedYet.selector);
        vinciStaking.withdraw();

        skip(5 days);
        vinciStaking.withdraw();

        vm.stopPrank();
    }

    function testConservationOfInternalBalancesWhenUnstaking() public {
        uint256 unstakeAmount = stakeAmount / 3;
        _airdrop(user, 10000 ether);
        skip(35 days);

        uint256 initialStaking = vinciStaking.activeStaking(user);
        uint256 initialUnstaking = vinciStaking.currentlyUnstakingBalance(user);
        uint256 initialTotalRewards = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 initialPenalatyPool = vinciStaking.penaltyPot();

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);

        assertEq(
            vinciStaking.activeStaking(user) + vinciStaking.currentlyUnstakingBalance(user),
            initialStaking + initialUnstaking,
            "balances conservation failed"
        );
        // the view functions can cause some rounding inaccuracies, but very very small
        assertApproxEqAbs(
            initialTotalRewards + initialPenalatyPool,
            vinciStaking.getTotalUnclaimableBalance(user) + vinciStaking.penaltyPot(),
            1,
            "rewards conservation failed"
        );
    }

    function testDoubleUnstakeDelaysReleaseTime() public {
        uint256 unstakeAmount = stakeAmount / 4;
        assertEq(vinciStaking.unstakingReleaseTime(user), 0);

        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);
        assertEq(vinciStaking.unstakingReleaseTime(user), block.timestamp + 14 days);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), unstakeAmount);

        skip(5 days);

        vinciStaking.unstake(unstakeAmount);
        assertEq(vinciStaking.unstakingReleaseTime(user), block.timestamp + 14 days);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), 2 * unstakeAmount);
    }

    function testDoubleUnstakeReducesRewardsWtice() public {
        skip(56 days);
        _airdrop(user, 2500 ether);

        uint256 unclaimable = vinciStaking.getTotalUnclaimableBalance(user);

        vm.startPrank(user);
        vinciStaking.unstake(stakeAmount / 2);
        assertApproxEqAbs(vinciStaking.getTotalUnclaimableBalance(user), unclaimable / 2, 10);

        skip(5 days);
        unclaimable = vinciStaking.getTotalUnclaimableBalance(user);
        vinciStaking.unstake(stakeAmount / 4);
        assertApproxEqAbs(vinciStaking.getTotalUnclaimableBalance(user), unclaimable / 2, 10);
    }

    function testUnstakeMoreThanActiveStaking() public {
        vm.startPrank(user);
        vm.expectRevert(VinciStakingV1.NotEnoughStakingBalance.selector);
        vinciStaking.unstake(stakeAmount + 1);

        // this should be fine
        vinciStaking.unstake(stakeAmount);

        vm.stopPrank();
    }

    function testRewardsReducedFromAllThreeSources() public {
        skip(187 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        assert(vinciStaking.isSuperstaker(user));
        assertGt(vinciStaking.activeStaking(user), 0);

        _fillAndDistributePenaltyPotOrganically();
        _airdrop(user, 10000 ether);

        uint256 _TotalUnclaimableBalance = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 _UnclaimableFromBaseApr = vinciStaking.getUnclaimableFromBaseApr(user);
        uint256 _UnclaimableFromPenaltyPot = vinciStaking.getUnclaimableFromPenaltyPot(user);
        uint256 _UnclaimableFromAirdrops = vinciStaking.getUnclaimableFromAirdrops(user);

        assertGt(_TotalUnclaimableBalance, 0);
        assertGt(_UnclaimableFromBaseApr, 0);
        assertGt(_UnclaimableFromPenaltyPot, 0);
        assertGt(_UnclaimableFromAirdrops, 0);

        vm.startPrank(user);
        vinciStaking.unstake(vinciStaking.activeStaking(user) / 7);
        vm.stopPrank();

        assertGt(_TotalUnclaimableBalance, vinciStaking.getTotalUnclaimableBalance(user));
        assertGt(_UnclaimableFromBaseApr, vinciStaking.getUnclaimableFromBaseApr(user));
        assertGt(_UnclaimableFromPenaltyPot, vinciStaking.getUnclaimableFromPenaltyPot(user));
        assertGt(_UnclaimableFromAirdrops, vinciStaking.getUnclaimableFromAirdrops(user));
    }

    function testUnstakedEvent() public {
        uint256 unstakeAmount = 500 ether;
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user, unstakeAmount);
        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);
    }

    function testViewClaimableBalanceAfterStaking() public {
        uint256 amount = 1000 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        skip(10 days);

        uint256 unstakeAmount = 500 ether;
        vinciStaking.unstake(unstakeAmount);
        vm.stopPrank();

        skip(15 days);

        assertEq(vinciStaking.claimableBalance(user), 0);
    }

    function testIndependenceBetweenClaimsAndUnclaimableBalances() public {
        uint256 stakeAmount = 1000 ether;
        vinciToken.mint(user, stakeAmount);
        vinciToken.mint(alice, stakeAmount);

        // alice's stake is only to fill later the penalty pot
        vm.startPrank(alice);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        skip(9 * 30 days);
        vm.stopPrank();

        // cross the checkpoint, to be a superstaker and be entiteld to penalty pot share
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        vm.prank(alice);
        vinciStaking.crossCheckpoint();

        vm.prank(alice);
        vinciStaking.unstake(10 ether);
        // although the current claimable from penalty pot is zero, the estimation including the non-distributed shoult be gt zero
        assertGt(vinciStaking.estimatedShareOfPenaltyPot(user), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(user), 0);

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();
        assertGt(vinciStaking.estimatedShareOfPenaltyPot(user), 0);
        assertGt(vinciStaking.getUnclaimableFromPenaltyPot(user), 0);
        // right after distribution, both should be the same
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(user), vinciStaking.estimatedShareOfPenaltyPot(user));

        address[] memory users = new address[](1);
        users[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        vm.prank(funder);
        vinciStaking.batchAirdrop(users, amounts);

        uint256 unclaimableFromBaseApr = vinciStaking.getUnclaimableFromBaseApr(user);
        uint256 unclaimableFromAirdrops = vinciStaking.getUnclaimableFromAirdrops(user);
        uint256 unclaimableFromPenaltyPot = vinciStaking.getUnclaimableFromPenaltyPot(user);

        // conditions before crossing checkpoint
        assertGt(vinciStaking.getTotalUnclaimableBalance(user), 0);
        assertGt(unclaimableFromBaseApr, 0);
        assertGt(unclaimableFromAirdrops, 0);
        assertGt(unclaimableFromPenaltyPot, 0);
    }

    function unstakeBeforeCheckpointCrossing() public {
        skip(7 * 30 days);
        assert(vinciStaking.canCrossCheckpoint(user));

        vm.startPrank(user);
        vm.expectRevert(VinciStakingV1.CheckpointHasToBeCrossedFirst.selector);
        vinciStaking.unstake(stakeAmount / 3);

        // and this should be fine
        vinciStaking.crossCheckpoint();
        vinciStaking.unstake(stakeAmount / 3);
    }
}

contract UnstakingTestsNotFunded is BaseTestNotFunded {
    function testSmallFundStakeRunOutOfFundsUnstake() public {
        vm.startPrank(user);
        uint256 amount = 100_000 ether;
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);
        assertEq(vinciStaking.activeStaking(user), amount);

        vinciStaking.unstake(amount);

        assertEq(vinciStaking.activeStaking(user), 0);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), amount);
        skip(15 days);

        uint256 balanceBefore = vinciToken.balanceOf(user);
        vinciStaking.withdraw();
        assertEq(vinciToken.balanceOf(user), balanceBefore + amount);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), 0);
    }

    function testSmallFundStakeRunOutOfFundsUnstakeAfterCrossingCheckpoint() public {}
}
