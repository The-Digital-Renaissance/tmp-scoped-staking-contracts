// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract TestWithdraws is BaseLPTestFunded {
    function testWithdrawTimes(uint64 nmonths, uint256 waitingTime) public {
        nmonths = (nmonths % 2 + 1) * 4;
        waitingTime = waitingTime % (18 * 30 days);

        uint256 amount = 0.33333 ether;

        lptoken.mint(holder1, 1 ether);

        vm.prank(holder1);
        stakingcontract.newStake(amount, nmonths);
        uint128 stakeTime = uint64(block.timestamp);
        uint256 releaseTime = uint256(stakeTime) + nmonths * 30 days;

        assertEq(amount, stakingcontract.getStakeAmount(holder1, 0));
        assertEq(uint64(releaseTime), stakingcontract.getStakeReleaseTime(holder1, 0));

        skip(waitingTime);
        if (block.timestamp >= releaseTime) {
            uint256 LPbalanceBefore = lptoken.balanceOf(holder1);
            vm.prank(holder1);
            stakingcontract.withdrawStake(0);
            assertEq(lptoken.balanceOf(holder1), LPbalanceBefore + amount);
        } else {
            vm.expectRevert(VinciLPStaking.StakeNotReleased.selector);
            vm.prank(holder1);
            stakingcontract.withdrawStake(0);
        }
    }

    function testWithdrawTwoTimesSameIndex() public {
        uint256 amount = 0.717171 ether;

        lptoken.mint(holder1, 1 ether);

        vm.prank(holder1);
        stakingcontract.newStake(amount, 8);

        // wait until stake is released
        vm.warp(stakingcontract.getStakeReleaseTime(holder1, 0) + 1);
        // this should work fine
        vm.prank(holder1);
        stakingcontract.withdrawStake(0);

        vm.prank(holder1);
        vm.expectRevert(VinciLPStaking.AlreadyWithdrawnIndex.selector);
        stakingcontract.withdrawStake(0);
    }

    function testWithdrawNonExistingIndex() public {
        uint256 amount = 0.717171 ether;
        lptoken.mint(holder1, 1 ether);

        vm.prank(holder1);
        stakingcontract.newStake(amount, 8);

        // wait until stake is released
        vm.warp(stakingcontract.getStakeReleaseTime(holder1, 0) + 1);

        vm.prank(holder1);
        vm.expectRevert(VinciLPStaking.NonExistingIndex.selector);
        stakingcontract.withdrawStake(1);
    }

    function testClaimableBeforeAfterWithdraws() public {
        uint256 amount = 1 ether;
        lptoken.mint(holder1, 3 ether);

        vm.startPrank(holder1);
        stakingcontract.newStake(amount, 4);
        stakingcontract.newStake(amount, 8);
        stakingcontract.newStake(amount, 12);
        // getting rid of any token just to avoid keeping track of `balanceBefore` in following tests
        vinciToken.transfer(holder2, vinciToken.balanceOf(holder1));
        vm.stopPrank();
        assertEq(lptoken.balanceOf(holder1), 0);
        assertEq(vinciToken.balanceOf(holder1), 0);

        skip(7 days);
        stakingcontract.distributeWeeklyAPR();
        skip(8 days);
        stakingcontract.distributeWeeklyAPR();
        skip(21 days);
        stakingcontract.distributeWeeklyAPR();

        uint256 weeklyClaimable0 = stakingcontract.readCurrentClaimable(holder1, 0);
        uint256 weeklyClaimable1 = stakingcontract.readCurrentClaimable(holder1, 1);
        uint256 weeklyClaimable2 = stakingcontract.readCurrentClaimable(holder1, 2);
        uint256 finalclaim0 = stakingcontract.readFinalPayout(holder1, 0);
        uint256 finalclaim1 = stakingcontract.readFinalPayout(holder1, 1);
        uint256 finalclaim2 = stakingcontract.readFinalPayout(holder1, 2);

        assertEq(weeklyClaimable0, finalclaim2);
        assertEq(weeklyClaimable2, finalclaim0);
        assertEq(weeklyClaimable1, finalclaim1);

        skip(4 * 30 days);

        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), finalclaim0);

        vm.prank(holder1);
        stakingcontract.withdrawStake(0);

        // all claims from the 4months period go to buffer
        assertEq(vinciToken.balanceOf(holder1), finalclaim0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 1), weeklyClaimable1);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 2), weeklyClaimable2);

        skip(5 * 30 days);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 1), weeklyClaimable1 + finalclaim1);

        vm.prank(holder1);
        stakingcontract.withdrawStake(1);

        assertEq(vinciToken.balanceOf(holder1), finalclaim0 + weeklyClaimable1 + finalclaim1);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 1), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 2), weeklyClaimable2);

        skip(4 * 30 days);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 2), weeklyClaimable2);

        vm.prank(holder1);
        stakingcontract.withdrawStake(2);

        assertEq(vinciToken.balanceOf(holder1), finalclaim0 + weeklyClaimable1 + finalclaim1 + weeklyClaimable2);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 0), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 1), 0);
        assertEq(stakingcontract.readCurrentClaimable(holder1, 2), 0);
    }
}
