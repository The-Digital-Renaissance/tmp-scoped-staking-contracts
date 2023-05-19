// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract TestViewFunctions is BaseLPTestFunded {
    function testReadStake() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amountLP = 1 ether;
        uint64 nmonths = 8;
        uint128 releaseTime = uint64(block.timestamp + 8 * 30 days);
        stakingcontract.newStake(amountLP, nmonths);

        assertEq(lptoken.balanceOf(address(stakingcontract)), amountLP);
        assertEq(lptoken.balanceOf(address(stakingcontract)), stakingcontract.totalStakedLPTokens());

        skip(7 days + 1);
        stakingcontract.distributeWeeklyAPR();

        uint256 claimable = stakingcontract.readCurrentClaimable(holder1, 0);

        vm.prank(holder1);
        stakingcontract.claimRewards(0);

        VinciLPStaking.Stake memory stake = stakingcontract.readStake(holder1, 0);
        assertEq(stake.amount, amountLP);
        assertEq(stake.releaseTime, releaseTime);
        assertEq(stake.monthsLocked, nmonths);
        assertEq(stake.withdrawn, false);

        skip(30 days * 13);
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();
        stakingcontract.distributeWeeklyAPR();

        uint256 newClaimable = stakingcontract.readCurrentClaimable(holder1, 0);
        assertGt(newClaimable, claimable);

        // make sure the withdraw also triggers the claim
        assertGt(vinciToken.balanceOf(address(stakingcontract)), 0);
        assertGt(lptoken.balanceOf(address(stakingcontract)), 0);

        uint256 vinciBalanceBefore = vinciToken.balanceOf(holder1);
        vm.prank(holder1);
        stakingcontract.withdrawStake(0);
        assertEq(vinciToken.balanceOf(holder1), vinciBalanceBefore + newClaimable);

        stake = stakingcontract.readStake(holder1, 0);
        assertEq(stake.amount, amountLP);
        assertEq(stake.releaseTime, releaseTime);
        assertEq(stake.monthsLocked, nmonths);
        assertEq(stake.withdrawn, true);
    }
}
