// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// PENALTY POT TESTS
// unstaking of user deposits to penalty pot from APR rewards
// unstaking of user deposits to penalty pot from airdrop rewards
// unstaking of user deposits to penalty pot from penaltypot allocated rewards
// deposits to ppot increases estimated share of other user
// deposits to ppot increase the total penalty pot or the buffered vinci
// deposits to ppot does not increase the allocated share of ppot (unclaimableFromPenaltyPot)
// distribution of ppot increases the unclaimableFromPenaltyPot of superstakers
// distribution of ppot does not affect non-superstakers
// several additions and removals do not lead to lost decimals due to elegible supply
// crossing checkpoint moves unclaimableFromPenaltyPot to claimable
// crossing checkpoint sets unclaimableFromPenaltyPot and estimatedShare to 0
// addition to elegible supply when crossing checkpoint
// addtion to elegible supply when superstaker stakes more
// subtraction from elegible supply when superstaker unstakes
// decimals of elegible supply
// thoroughly test elegible supply and decimals stuff

/// Reminder
// unstake fills penalty pot
// distribute empties penalty pot, and moves them to unclaimables
// crossing checkpoint moves unclaimables to unclaimables

contract BasePenaltyPotTests is BaseTestFunded {
    uint256 amount = 1_000_000 ether;

    address randomguy = 0xC0373D7169D1Bf8572957D217ea6cAa974eC9a08;

    function setUp() public override {
        super.setUp();

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

        vm.startPrank(user);
        vinciToken.mint(user, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(5 * amount);
        vm.stopPrank();

        assertEq(vinciStaking.totalVinciStaked(), 23 * amount);

        skip(185 days);

        address[] memory superStakers = new address[](4);
        superStakers[0] = bob;
        superStakers[1] = alice;
        superStakers[2] = pepe;
        superStakers[3] = user;
        vm.prank(operator);
        vinciStaking.crossCheckpointTo(superStakers);
    }
}

contract TestPenaltyPot is BasePenaltyPotTests {
    event DepositedToPenaltyPot(address user, uint256 amountDeposited);

    function testPenaltyFromAPRisDepositedSimple() public {
        skip(67 days);
        uint256 activeBalance = vinciStaking.activeStaking(bob);
        uint256 unstakeAmount = 2 * amount;
        uint256 fromApr = vinciStaking.getUnclaimableFromBaseApr(bob);
        uint256 ppotBefore = vinciStaking.penaltyPot();

        vm.prank(bob);
        vinciStaking.unstake(unstakeAmount);

        uint256 penalty = fromApr * unstakeAmount / activeBalance;
        assertEq(vinciStaking.penaltyPot(), ppotBefore + penalty);
    }

    function testPenaltyFromAPRisDepositedBySeveralStakers() public {
        skip(91 days + 1234);
        uint256 ppotBeforeBob = vinciStaking.penaltyPot();
        uint256 bobFromApr = vinciStaking.getUnclaimableFromBaseApr(bob);
        uint256 bobStaked = vinciStaking.activeStaking(bob);
        vm.prank(bob);
        vinciStaking.unstake(amount);
        assertApproxEqAbs(vinciStaking.penaltyPot() - ppotBeforeBob, bobFromApr * amount / bobStaked, 10);

        uint256 ppotBeforeAlice = vinciStaking.penaltyPot();
        uint256 aliceFromApr = vinciStaking.getUnclaimableFromBaseApr(alice);
        uint256 aliceStaked = vinciStaking.activeStaking(alice);
        vm.prank(alice);
        vinciStaking.unstake(amount);
        assertApproxEqAbs(vinciStaking.penaltyPot() - ppotBeforeAlice, aliceFromApr * amount / aliceStaked, 10);
    }

    function testPenaltyFromAirdropIsDepositedByUser() public {
        uint256 airdropped = 10_000_123 ether;
        _airdrop(user, airdropped);
        uint256 staked = vinciStaking.activeStaking(user);
        uint256 penaltyPotBefore = vinciStaking.penaltyPot();
        uint256 unclaimableFromAirdopr = vinciStaking.getUnclaimableFromAirdrops(user);
        uint256 totalUnclaimable = vinciStaking.getTotalUnclaimableBalance(user);
        assertEq(unclaimableFromAirdopr, airdropped);
        assertGt(totalUnclaimable, airdropped);

        vm.prank(user);
        vinciStaking.unstake(amount);

        uint256 estimatedPenaltyOnAirdrop = unclaimableFromAirdopr * amount / staked;
        uint256 estimatedPenalty = totalUnclaimable * amount / staked;
        uint256 penaltyToAirdrop = unclaimableFromAirdopr - vinciStaking.getUnclaimableFromAirdrops(user);
        uint256 penalty = totalUnclaimable - vinciStaking.getTotalUnclaimableBalance(user);

        assertEq(estimatedPenalty, penalty);
        assertEq(estimatedPenaltyOnAirdrop, penaltyToAirdrop);

        // penalty / totalUnclaimable = unstake / stake
        // penalty * stake = unstake * airdropped
        assertApproxEqRel(penalty * staked, amount * totalUnclaimable, 10);
        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore + penalty);
        assertApproxEqAbs(vinciStaking.getTotalUnclaimableBalance(user), totalUnclaimable - penalty, 10);
        assertApproxEqAbs(vinciStaking.getUnclaimableFromAirdrops(user), unclaimableFromAirdopr - penaltyToAirdrop, 10);
    }

    function testPenaltyToAirdropsConservationOfBalancesWithAirdrops() public {
        _airdrop(pepe, 10_000_000 ether);
        _airdrop(alice, 700_001 ether);
        _airdrop(bob, 10_001 ether);

        uint256 penaltyPotBefore = vinciStaking.penaltyPot();
        uint256 totalAprEarned = vinciStaking.getUnclaimableFromBaseApr(pepe)
            + vinciStaking.getUnclaimableFromBaseApr(alice) + vinciStaking.getUnclaimableFromBaseApr(bob);
        uint256 totalAirdropped = vinciStaking.getUnclaimableFromAirdrops(pepe)
            + vinciStaking.getUnclaimableFromAirdrops(alice) + vinciStaking.getUnclaimableFromAirdrops(bob);
        assertEq(totalAirdropped, 10_710_002 ether);

        vm.prank(bob);
        vinciStaking.unstake(amount);
        vm.prank(alice);
        vinciStaking.unstake(amount);
        vm.prank(pepe);
        vinciStaking.unstake(amount);

        uint256 remainingAirdropped = vinciStaking.getUnclaimableFromAirdrops(pepe)
            + vinciStaking.getUnclaimableFromAirdrops(alice) + vinciStaking.getUnclaimableFromAirdrops(bob);
        uint256 remainingApr = vinciStaking.getUnclaimableFromBaseApr(pepe)
            + vinciStaking.getUnclaimableFromBaseApr(alice) + vinciStaking.getUnclaimableFromBaseApr(bob);

        uint256 totalPenaltyToApr = totalAprEarned - remainingApr;
        uint256 totalPenaltyToAirdrops = totalAirdropped - remainingAirdropped;
        assertApproxEqAbs(vinciStaking.penaltyPot(), penaltyPotBefore + totalPenaltyToAirdrops + totalPenaltyToApr, 10);
    }

    function testPenaltyFromAirdropOneUser() public {
        vm.startPrank(randomguy);
        vinciToken.mint(randomguy, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(3 * amount);
        vm.stopPrank();

        _airdrop(randomguy, 700_001 ether);
        uint256 airdropped = vinciStaking.getUnclaimableFromAirdrops(randomguy);
        uint256 staked = vinciStaking.activeStaking(randomguy);
        assertEq(airdropped, 700_001 ether);

        vm.prank(randomguy);
        uint256 unstaked = 2 * amount;
        vinciStaking.unstake(unstaked);

        uint256 remainingAirdropped = vinciStaking.getUnclaimableFromAirdrops(randomguy);
        uint256 airdropPenalty = airdropped - remainingAirdropped;

        assertApproxEqAbs(airdropPenalty, vinciStaking.penaltyPot(), 1);
        assertApproxEqRel(airdropPenalty, unstaked * airdropped / staked, 1000);
    }

    function testBasicUnstakeAndFillPenaltyPot() public {
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(100 days);

        uint256 unstakeAmount = 245 ether;
        uint256 unclaimable = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 estimatedPenalty = _estimatePenalty(user, unstakeAmount);

        uint256 penaltyPotBefore = vinciStaking.penaltyPot();
        vinciStaking.unstake(unstakeAmount);

        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore + estimatedPenalty);
        assertEq(vinciStaking.getTotalUnclaimableBalance(user), unclaimable - estimatedPenalty);

        vm.stopPrank();
    }

    function testUnstakeAndFillPenaltyPotDouble() public {
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        uint256 penaltyPotBefore = vinciStaking.penaltyPot();

        skip(100 days);

        uint256 unstakeAmount = 245 ether;
        uint256 totalPenalty = _estimatePenalty(user, unstakeAmount);
        vinciStaking.unstake(unstakeAmount);

        skip(30 days);
        uint256 unstakeAmount2 = 138 ether;
        uint256 penalty2 = _estimatePenalty(user, unstakeAmount2);
        totalPenalty += penalty2;
        vinciStaking.unstake(unstakeAmount2);

        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore + totalPenalty);

        vm.stopPrank();
    }

    function testFillPenaltyPotMultipleAddresses() public {
        uint256 penaltyPotBefore = vinciStaking.penaltyPot();

        skip(100 days);
        uint256 aliceUnstakeAmount = 100 ether;
        uint256 bobUnstakeAmount = 200 ether;
        uint256 pepeUnstakeAmount = 300 ether;
        uint256 penaltyAlice = _estimatePenalty(alice, aliceUnstakeAmount);
        uint256 penaltyBob = _estimatePenalty(bob, bobUnstakeAmount);
        uint256 penaltypepe = _estimatePenalty(pepe, pepeUnstakeAmount);

        vm.prank(alice);
        vinciStaking.unstake(aliceUnstakeAmount);
        vm.prank(bob);
        vinciStaking.unstake(bobUnstakeAmount);
        vm.prank(pepe);
        vinciStaking.unstake(pepeUnstakeAmount);

        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore + penaltyAlice + penaltyBob + penaltypepe);
    }

    function testPenaltyPotEvent() public {
        uint256 stakeAmount = 1000 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(100 days);

        uint256 unstakeAmount = 245 ether;
        uint256 estimatedPenalty = _estimatePenalty(user, unstakeAmount);

        vm.expectEmit(true, false, false, true);
        emit DepositedToPenaltyPot(user, estimatedPenalty);
        vinciStaking.unstake(unstakeAmount);

        vm.stopPrank();
    }

    function testConservationOfPenaltyPotWhenDistributed() public {
        _fillAndDistributePenaltyPotOrganically();

        uint256 penaltyPotBefore = vinciStaking.penaltyPot();
        assertGt(penaltyPotBefore, 0);

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore);
    }

    function testConservationOfPotWhenCrossingCheckpoint() public {
        _fillAndDistributePenaltyPotOrganically();
        skip(6 * 31 days);
        vm.prank(operator);
        vinciStaking.distributePenaltyPot();
        uint256 penaltyPotBefore = vinciStaking.penaltyPot();

        vm.prank(user);
        vinciStaking.crossCheckpoint();

        assertEq(vinciStaking.penaltyPot(), penaltyPotBefore);
    }

    function testFillPenaltyPotOrganically() public {
        _fillAndDistributePenaltyPotOrganically();
        assertGt(vinciStaking.penaltyPot(), 0);

        assertGt(vinciStaking.getUnclaimableFromPenaltyPot(alice), 0);
        assertGt(vinciStaking.getUnclaimableFromPenaltyPot(bob), 0);
        assertGt(vinciStaking.getUnclaimableFromPenaltyPot(pepe), 0);
    }

    function testRedistributionOfPpotSimple() public {
        vm.prank(alice);
        vinciStaking.unstake(2 * amount);
        vm.prank(bob);
        vinciStaking.unstake(1 * amount);
        vm.prank(pepe);
        vinciStaking.unstake(1 * amount);

        uint256 ppotBefore = vinciStaking.penaltyPot();
        assertGt(ppotBefore, 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(alice), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(pepe), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(bob), 0);

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        uint256 aliceAllocation = vinciStaking.getUnclaimableFromPenaltyPot(alice);
        uint256 pepeAllocation = vinciStaking.getUnclaimableFromPenaltyPot(pepe);
        uint256 bobAllocation = vinciStaking.getUnclaimableFromPenaltyPot(bob);
        assertGt(aliceAllocation, 0);
        assertGt(pepeAllocation, 0);
        assertGt(bobAllocation, 0);
    }

    function testAdditionToEleigbleSupplyWhenCrossingCheckpoint() public {
        vm.startPrank(randomguy);
        vinciToken.mint(randomguy, 10 * amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(10 * amount);
        vm.stopPrank();

        uint256 staked = vinciStaking.activeStaking(randomguy);
        assert(!vinciStaking.isSuperstaker(randomguy));
        uint256 elegibleSupplyBefore = vinciStaking.getSupplyEligibleForPenaltyPot();

        skip(181 days);
        vm.prank(randomguy);
        vinciStaking.crossCheckpoint();

        assertEq(vinciStaking.getSupplyEligibleForPenaltyPot(), elegibleSupplyBefore + staked);
    }

    function testAdditionToEleigbleSupplyWhenSuperStakerStakesAgain(uint256 extraStake) public {
        skip(181 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();

        uint256 elegibleSupplyBefore = vinciStaking.getSupplyEligibleForPenaltyPot();

        extraStake = bound(extraStake, 1, vinciToken.balanceOf(user));

        vm.prank(user);
        vinciStaking.stake(extraStake);

        assertApproxEqAbs(
            vinciStaking.getSupplyEligibleForPenaltyPot(),
            elegibleSupplyBefore + extraStake,
            vinciStaking.PENALTYPOT_ROUNDING_FACTOR()
        );
    }

    function testAdditionToEleigbleSupplyWhenSuperStakerUnstakes(uint256 unstaked) public {
        uint256 staked = vinciStaking.activeStaking(user);
        skip(181 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();

        uint256 elegibleSupplyBefore = vinciStaking.getSupplyEligibleForPenaltyPot();

        unstaked = bound(unstaked, 1, staked);
        vm.prank(user);
        vinciStaking.unstake(unstaked);

        assertApproxEqAbs(vinciStaking.getSupplyEligibleForPenaltyPot(), elegibleSupplyBefore - unstaked, 10);
    }

    function testElegibleSupplyReducesToZeroWhenEveryoneUnstakes() public {
        vm.startPrank(alice);
        vinciStaking.unstake(vinciStaking.activeStaking(alice));
        vm.stopPrank();
        vm.startPrank(bob);
        vinciStaking.unstake(vinciStaking.activeStaking(bob));
        vm.stopPrank();
        vm.startPrank(pepe);
        vinciStaking.unstake(vinciStaking.activeStaking(pepe));
        vm.stopPrank();
        vm.startPrank(user);
        vinciStaking.unstake(vinciStaking.activeStaking(user));
        vm.stopPrank();

        assertEq(vinciStaking.getSupplyEligibleForPenaltyPot(), 0);
    }

    function testDistributionWithNoSupply() public {
        vm.startPrank(alice);
        vinciStaking.unstake(vinciStaking.activeStaking(alice));
        vm.stopPrank();
        vm.startPrank(bob);
        vinciStaking.unstake(vinciStaking.activeStaking(bob));
        vm.stopPrank();
        vm.startPrank(pepe);
        vinciStaking.unstake(vinciStaking.activeStaking(pepe));
        vm.stopPrank();
        vm.startPrank(user);
        vinciStaking.unstake(vinciStaking.activeStaking(user));
        vm.stopPrank();

        _fillPotWithoutDistribution();

        uint256 ppotBefore = vinciStaking.penaltyPot();
        assertGt(ppotBefore, 0);

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        assertEq(vinciStaking.penaltyPot(), ppotBefore);
    }

    function testDistributionOfPenaltyPot() public {
        vm.prank(bob);
        vinciStaking.unstake(1 * amount);
        vm.prank(pepe);
        vinciStaking.unstake(2 * amount);
        vm.prank(alice);
        vinciStaking.unstake(1 * amount);

        assertGt(vinciStaking.penaltyPot(), 0);
        assertGt(vinciStaking.getSupplyEligibleForPenaltyPot(), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(alice), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(bob), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(pepe), 0);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(user), 0);

        uint256 penaltyPotBefore = vinciStaking.penaltyPot();

        // allocations are only updated when distribution happens
        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        uint256 aliceAllocation = vinciStaking.getUnclaimableFromPenaltyPot(alice);
        uint256 bobAllocation = vinciStaking.getUnclaimableFromPenaltyPot(bob);
        uint256 pepeAllocation = vinciStaking.getUnclaimableFromPenaltyPot(pepe);
        uint256 userAllocation = vinciStaking.getUnclaimableFromPenaltyPot(user);
        assertGt(aliceAllocation, 0);
        assertGt(bobAllocation, 0);
        assertGt(pepeAllocation, 0);
        assertGt(userAllocation, 0);

        assertEq(
            penaltyPotBefore,
            vinciStaking.penaltyPot() + aliceAllocation + bobAllocation + pepeAllocation + userAllocation
        );
    }

    function testUnclaimableInvariantWhenStakingMore() public {
        skip(181 days);
        vm.startPrank(alice);
        vinciStaking.crossCheckpoint();
        vinciStaking.unstake(amount);
        vm.stopPrank();
        vm.startPrank(bob);
        vinciStaking.crossCheckpoint();
        vinciStaking.unstake(amount);
        vm.stopPrank();
        vm.startPrank(pepe);
        vinciStaking.crossCheckpoint();
        vinciStaking.unstake(amount);
        vm.stopPrank();

        // allocations are only updated when distribution happens
        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        uint256 aliceAllocation = vinciStaking.getUnclaimableFromPenaltyPot(alice);
        uint256 bobAllocation = vinciStaking.getUnclaimableFromPenaltyPot(bob);
        uint256 pepeAllocation = vinciStaking.getUnclaimableFromPenaltyPot(pepe);

        vm.prank(alice);
        vinciStaking.stake(amount);
        assertEq(aliceAllocation, vinciStaking.getUnclaimableFromPenaltyPot(alice));
        assertEq(bobAllocation, vinciStaking.getUnclaimableFromPenaltyPot(bob));
        assertEq(pepeAllocation, vinciStaking.getUnclaimableFromPenaltyPot(pepe));
    }

    function testUnstakePenaltyPotShareReductionFuzzy(uint256 unstakeAmount) public {
        //        skip(155 days);
        //        vm.prank(user);
        //        vinciStaking.crossCheckpoint();
        //        vm.prank(alice);
        //        vinciStaking.crossCheckpoint();
        //        vm.prank(bob);
        //        vinciStaking.crossCheckpoint();
        //        vm.prank(pepe);
        //        vinciStaking.crossCheckpoint();

        skip(37 days);
        uint256 staked = vinciStaking.activeStaking(user);
        unstakeAmount = bound(unstakeAmount, 1, staked - 1);
        uint256 rewards = vinciStaking.getTotalUnclaimableBalance(user);
        assertGt(rewards, 0);

        // share of the penalty pot should be reduced proportionally unstake amount and the elegible supply
        uint256 estimatedPenalty = rewards * unstakeAmount / staked;
        // this amount will go back to the user if still has some staked and keeps status of superuser
        uint256 stillStaked = staked - unstakeAmount;
        uint256 shareThatGoesBackToUser =
            estimatedPenalty * stillStaked / (vinciStaking.getSupplyEligibleForPenaltyPot() - unstakeAmount);

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);
        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        // conservation of balances
        // penalty pot after == penalty pot before + estimatedPenalty
        // penalty pot before == sum of unclaimables from penalty pot before
        // penalty pot after == sum of unclaimables from penalty pot after
        // the allowed error is the PENALTYPOT_ROUNDING_FACTOR, because the elegible supply is rounded by that
        assertApproxEqAbs(
            vinciStaking.getTotalUnclaimableBalance(user),
            rewards - estimatedPenalty + shareThatGoesBackToUser,
            vinciStaking.PENALTYPOT_ROUNDING_FACTOR()
        );
    }

    function testPenaltyPotConservationOfBalancesAfterUnstake(uint256 unstakeAmount) public {
        skip(182 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        vm.prank(alice);
        vinciStaking.crossCheckpoint();
        vm.prank(bob);
        vinciStaking.crossCheckpoint();
        vm.prank(pepe);
        vinciStaking.crossCheckpoint();
        assertGt(vinciStaking.getSupplyEligibleForPenaltyPot(), 0);

        skip(37 days);
        uint256 staked = vinciStaking.activeStaking(user);
        unstakeAmount = bound(unstakeAmount, 1, staked);

        uint256 ppotBefore = vinciStaking.penaltyPot();
        uint256 unclaimablesFromPpotBefore = vinciStaking.getUnclaimableFromPenaltyPot(user)
            + vinciStaking.getUnclaimableFromPenaltyPot(alice) + vinciStaking.getUnclaimableFromPenaltyPot(bob)
            + vinciStaking.getUnclaimableFromPenaltyPot(pepe);
        uint256 userTotalUnclaimableBefore = vinciStaking.getTotalUnclaimableBalance(user);

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        uint256 userTotalUnclaimableAfter = vinciStaking.getTotalUnclaimableBalance(user);
        uint256 userPenalty = userTotalUnclaimableBefore - userTotalUnclaimableAfter;
        uint256 ppotAfterUnstake = vinciStaking.penaltyPot();
        uint256 unclaimablesFromPpotAfterUnstake = vinciStaking.getUnclaimableFromPenaltyPot(user)
            + vinciStaking.getUnclaimableFromPenaltyPot(alice) + vinciStaking.getUnclaimableFromPenaltyPot(bob)
            + vinciStaking.getUnclaimableFromPenaltyPot(pepe);
        assertApproxEqAbs(ppotAfterUnstake, ppotBefore + userPenalty, 1, "ppot conservation issue");
        // these doesnt change until distribution
        assertEq(unclaimablesFromPpotBefore, unclaimablesFromPpotAfterUnstake);
    }

    function testPenaltyPotConservationOfBalancesAfterDistribution(uint256 unstakeAmount) public {
        skip(182 days);
        vm.prank(user);
        vinciStaking.crossCheckpoint();
        vm.prank(alice);
        vinciStaking.crossCheckpoint();
        vm.prank(bob);
        vinciStaking.crossCheckpoint();
        vm.prank(pepe);
        vinciStaking.crossCheckpoint();
        assertGt(vinciStaking.getSupplyEligibleForPenaltyPot(), 0);

        skip(37 days);
        uint256 staked = vinciStaking.activeStaking(user);
        unstakeAmount = bound(unstakeAmount, 1, staked);

        vm.prank(user);
        vinciStaking.unstake(unstakeAmount);

        uint256 totalUnclaimablesBefore = vinciStaking.getTotalUnclaimableBalance(user)
            + vinciStaking.getTotalUnclaimableBalance(alice) + vinciStaking.getTotalUnclaimableBalance(bob)
            + vinciStaking.getTotalUnclaimableBalance(pepe);
        uint256 aprUnclaimablesBefore = vinciStaking.getUnclaimableFromBaseApr(user)
            + vinciStaking.getUnclaimableFromBaseApr(alice) + vinciStaking.getUnclaimableFromBaseApr(bob)
            + vinciStaking.getUnclaimableFromBaseApr(pepe);
        uint256 ppotBefore = vinciStaking.penaltyPot();

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        // the unclaimables are redistributed among superstakers, but there should not be a net increase in total unclaimables
        uint256 ppotAfter = vinciStaking.penaltyPot();
        uint256 aprUnclaimablesAfter = vinciStaking.getUnclaimableFromBaseApr(user)
            + vinciStaking.getUnclaimableFromBaseApr(alice) + vinciStaking.getUnclaimableFromBaseApr(bob)
            + vinciStaking.getUnclaimableFromBaseApr(pepe);
        uint256 totalUnclaimablesAfter = vinciStaking.getTotalUnclaimableBalance(user)
            + vinciStaking.getTotalUnclaimableBalance(alice) + vinciStaking.getTotalUnclaimableBalance(bob)
            + vinciStaking.getTotalUnclaimableBalance(pepe);

        // this makes sure that we are only dealing with penalty pot redistribution
        assertEq(aprUnclaimablesBefore, aprUnclaimablesAfter);

        // The only change triggered by distribution should be in penalty pot and allocated unclaimables from penalty pot
        assertApproxEqRel(
            totalUnclaimablesBefore + ppotBefore,
            totalUnclaimablesAfter + ppotAfter,
            1e12,
            "conservation in distribution issue"
        );
    }
}
