// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

contract TestViewFunctions is BaseTestFunded {
    function testViewUnclaimableFromAPR() public {
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 stakeAmount = 1 ether;
        vinciStaking.stake(1 ether);

        uint256 rewardsFullPeriod = stakeAmount * 550 * 6 * 30 days / (10000 * 365 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), 0);

        // after 1 month, the unlocked rewards should be 1/6 of total
        skip(1 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertApproxEqRel(vinciStaking.getUnclaimableFromBaseApr(user), rewardsFullPeriod / 6, 0.000001 ether);

        // after half the period, the unlocked rewards should be half of the full period
        skip(2 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), rewardsFullPeriod / 2);

        // after 1 month, the unlocked rewards should be 1/6 of total
        skip(1 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertApproxEqRel(vinciStaking.getUnclaimableFromBaseApr(user), rewardsFullPeriod * 4 / 6, 0.000001 ether);
    }

    function testViewUnclaimableFromAPRAfterExtraStake() public {
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 stakeAmount = 1 ether;
        vinciStaking.stake(1 ether);

        uint256 rewardsFullPeriod = stakeAmount * 550 * 6 * 30 days / (10000 * 365 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), 0);

        // after 1 month, the unlocked rewards should be 1/6 of total
        skip(1 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertApproxEqRel(vinciStaking.getUnclaimableFromBaseApr(user), rewardsFullPeriod / 6, 0.000001 ether);

        // now another stake takes place. Current checkpoint possition does not move though
        vinciStaking.stake(1 ether);
        uint256 rewardsFullPeriod2stake = stakeAmount * 550 * 5 * 30 days / (10000 * 365 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod + rewardsFullPeriod2stake);
        // right now, the unlocked rewards are just the ones from the first staked, as the second one just happened
        assertApproxEqRel(vinciStaking.getUnclaimableFromBaseApr(user), rewardsFullPeriod / 6, 0.000001 ether);

        // if we skip another month, now the unlocked rewards comes from both stakes
        skip(1 * 30 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod + rewardsFullPeriod2stake);
        uint256 unlockedFromFristPeriod = 2 * rewardsFullPeriod / 6;
        uint256 unlockedFromSecondPeriod = rewardsFullPeriod2stake / 5; // only 5, because the lenght of second stake is only 5 months
        assertApproxEqRel(
            vinciStaking.getUnclaimableFromBaseApr(user),
            unlockedFromFristPeriod + unlockedFromSecondPeriod,
            0.00001 ether
        );
    }

    function testViewUnclaimableFromAPRAfterCrossingCheckpoint() public {
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 stakeAmount = 1 ether;
        vinciStaking.stake(1 ether);

        uint256 rewardsFullPeriod = stakeAmount * 550 * 6 * 30 days / (10000 * 365 days);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullPeriod);
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), 0);

        vm.warp(vinciStaking.nextCheckpointTimestamp(user) + 1);
        vinciStaking.crossCheckpoint();
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 30 days * 5 - 1);

        uint256 rewardsFullSecondPeriod = stakeAmount * 550 * 5 * 30 days / (10000 * 365 days);
        assertEq(vinciStaking.claimableBalance(user), rewardsFullPeriod);
        assertEq(vinciStaking.fullPeriodAprRewards(user), rewardsFullSecondPeriod);

        assert(!vinciStaking.canCrossCheckpoint(user));
        assertLe(vinciStaking.getUnclaimableFromBaseApr(user), _estimateRewards(2 * stakeAmount, 10));
    }

    function testViewBalancesWithZeros() public {
        assertEq(vinciStaking.getUnclaimableFromBaseApr(nonUser), 0);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(nonUser), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(nonUser), 0);
        assertEq(vinciStaking.getTotalUnclaimableBalance(nonUser), 0);
        assertEq(vinciStaking.nextCheckpointTimestamp(nonUser), 0);
        assertEq(vinciStaking.canCrossCheckpoint(nonUser), false);
        assertEq(vinciStaking.claimableBalance(nonUser), 0);
        assertEq(vinciStaking.activeStaking(nonUser), 0);
        assertEq(vinciStaking.currentlyUnstakingBalance(nonUser), 0);
        assertEq(vinciStaking.unstakingReleaseTime(nonUser), 0);
        assertEq(vinciStaking.fullPeriodAprRewards(nonUser), 0);
    }

    function testViewEstimatePenaltyPot() public {
        _fillPotWithoutDistribution();
        skip(180 days);
        vm.prank(alice);
        vinciStaking.crossCheckpoint();
        vm.prank(bob);
        vinciStaking.crossCheckpoint();
        vm.prank(pepe);
        vinciStaking.crossCheckpoint();

        assertGt(vinciStaking.penaltyPot(), 0);
        assertGt(vinciStaking.getSupplyEligibleForPenaltyPot(), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(alice), 0);
        assertApproxEqRel(
            vinciStaking.estimatedShareOfPenaltyPot(alice),
            vinciStaking.penaltyPot() * vinciStaking.activeStaking(alice)
                / vinciStaking.getSupplyEligibleForPenaltyPot(),
            vinciStaking.PENALTYPOT_ROUNDING_FACTOR()
        );

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        assertApproxEqAbs(
            vinciStaking.getUnclaimableFromPenaltyPot(alice), vinciStaking.estimatedShareOfPenaltyPot(alice), 1000
        );
    }
}
