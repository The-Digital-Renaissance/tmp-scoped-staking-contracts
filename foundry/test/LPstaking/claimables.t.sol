// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract TestLPclaimables is BaseLPTestFunded {
    function testClaimablesAfterStaking4months() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amountLP = 1 ether;
        uint64 nmonths = 4;
        stakingcontract.newStake(amountLP, nmonths);

        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();

        // 4 moths ==> nothing goes to weekly, all goes to the end
        uint256 expectedWeelyReward = 0;
        uint256 expectedFinalReward =
            (stakingcontract.WEEKLY_VINCI_REWARDS() * amountLP) / stakingcontract.totalStakedLPTokens();

        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), expectedWeelyReward);
        assertEq(stakingcontract.readFinalPayout(holder1, 0), expectedFinalReward);
    }

    function testClaimablesAfterStaking8months() public {
        lptoken.mint(holder1, 1 ether);

        uint256 amountLP = 1 ether;
        uint64 nmonths = 8;

        vm.prank(holder1);
        stakingcontract.newStake(amountLP, nmonths);

        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();

        // 4 moths ==> nothing goes to weekly, all goes to the end
        uint256 rewards = (stakingcontract.WEEKLY_VINCI_REWARDS() * amountLP) / stakingcontract.totalStakedLPTokens();
        console.log("rewards", rewards);

        assertApproxEqAbs(stakingcontract.readCurrentClaimable(holder1, 0), rewards / 2, 1);
        assertApproxEqAbs(stakingcontract.readFinalPayout(holder1, 0), rewards / 2, 1);
    }

    function testClaimablesAfterStaking12months() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amountLP = 1 ether;
        uint64 nmonths = 12;
        stakingcontract.newStake(amountLP, nmonths);

        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();

        // 4 moths ==> nothing goes to weekly, all goes to the end
        uint256 expectedWeelyReward =
            (stakingcontract.WEEKLY_VINCI_REWARDS() * amountLP) / stakingcontract.totalStakedLPTokens();
        uint256 expectedFinalReward = 0;
        console.log("expectedWeelyReward", expectedWeelyReward);

        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), expectedWeelyReward);
        assertEq(stakingcontract.readFinalPayout(holder1, 0), expectedFinalReward);
    }

    function testDistributeMultipleTimes8monthsLock() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amountLP = 0.6 ether;
        uint64 nmonths = 8;
        stakingcontract.newStake(amountLP, nmonths);

        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();
        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();
        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();

        // 4 moths ==> nothing goes to weekly, all goes to the end
        uint256 expectedReward =
            3 * (stakingcontract.WEEKLY_VINCI_REWARDS() * amountLP) / stakingcontract.totalStakedLPTokens();

        assertApproxEqAbs(stakingcontract.readCurrentClaimable(holder1, 0), expectedReward / 2, 1);
        assertApproxEqAbs(stakingcontract.readFinalPayout(holder1, 0), expectedReward / 2, 1);
    }

    function testAPRdistributionTooSoon() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amountLP = 0.777787 ether;
        uint64 nmonths = 8;
        stakingcontract.newStake(amountLP, nmonths);
        // this first time is happening before than a week has passed after depoyment
        vm.expectRevert(VinciLPStaking.APRDistributionTooSoon.selector);
        stakingcontract.distributeWeeklyAPR();

        skip(7 days + 1);
        // after one week, this one should be fine
        stakingcontract.distributeWeeklyAPR();
        // but we cannot distribute twice in the same week
        vm.expectRevert(VinciLPStaking.APRDistributionTooSoon.selector);
        stakingcontract.distributeWeeklyAPR();
    }

    function testClaimablesAndRewardsAggregated() public {
        lptoken.mint(holder1, 1 ether);
        lptoken.mint(holder2, 1 ether);

        uint256 amountLP = 1 ether;
        uint64 nmonths = 8;

        assertEq(vinciToken.balanceOf(holder1), 0);
        assertEq(vinciToken.balanceOf(holder2), 0);

        vm.prank(holder1);
        stakingcontract.newStake(amountLP, nmonths);
        vm.prank(holder2);
        stakingcontract.newStake(amountLP, nmonths);

        uint256 instantPayments1 = vinciToken.balanceOf(holder1);
        uint256 instantPayments2 = vinciToken.balanceOf(holder2);

        uint256 numberOfDistributions = 6;
        // divide by 2 for two holders, and by two again because of weely-vs-final (equivalent to divide by 4)
        uint256 weeklyDistributionPerHolder = stakingcontract.WEEKLY_VINCI_REWARDS() / 2 / 2;
        uint256 finalDistributionPerHolder = numberOfDistributions * stakingcontract.WEEKLY_VINCI_REWARDS() / 2 / 2;

        // skip seven months, to have some accumulated weekly APR to distribute
        skip(7 * 30 days + 1);
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        // up until now, only 4 weeks have been distributed, but as release time has not passed, only weekly is claimable
        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), 4 * weeklyDistributionPerHolder);
        assertEq(stakingcontract.readCurrentClaimable(holder2, 0), 4 * weeklyDistributionPerHolder);
        // now if they claim their rewards, their claimables should be zero
        vm.prank(holder1);
        stakingcontract.claimRewards(0);
        vm.prank(holder2);
        stakingcontract.claimRewards(0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder2, 0), 0);

        // lets distribute a couple of more times, and forward til the end of releaseTime
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        skip(2 * 30 days + 1);
        // make sure the stakes are released now
        assertGt(block.timestamp, stakingcontract.getStakeReleaseTime(holder1, 0));
        assertGt(block.timestamp, stakingcontract.getStakeReleaseTime(holder2, 0));

        // make sure the new claimables contain the two missing weeks plus the final part
        assertEq(
            stakingcontract.readCurrentClaimable(holder1, 0),
            2 * weeklyDistributionPerHolder + finalDistributionPerHolder
        );
        assertEq(
            stakingcontract.readCurrentClaimable(holder2, 0),
            2 * weeklyDistributionPerHolder + finalDistributionPerHolder
        );

        // lets withdraw and make sure the remaining VINCI claimables are also withdrawn with the LPtokens
        vm.prank(holder1);
        stakingcontract.withdrawStake(0);
        vm.prank(holder2);
        stakingcontract.withdrawStake(0);

        assertEq(lptoken.balanceOf(holder1), amountLP);
        assertEq(lptoken.balanceOf(holder2), amountLP);

        assertEq(
            vinciToken.balanceOf(holder1),
            instantPayments1 + (6 * weeklyDistributionPerHolder) + finalDistributionPerHolder
        );
        assertEq(
            vinciToken.balanceOf(holder2),
            instantPayments2 + (6 * weeklyDistributionPerHolder) + finalDistributionPerHolder
        );
    }
}
