// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract TestNonFundedContract is BaseLPTestNotFunded {
    // overall, if the contract is not funded, stake and withdraw should still work normally
    // except that the instant payment wont happen

    event InstantPayoutInVinci(address indexed _sender, uint256 _amount);
    event InsufficientVinciForInstantPayout(address indexed staker, uint256 correspondingPayout, uint256 missedPayout);

    // APR distribution should revert as there is no vinci to distribute

    function testStakeWithoutFunds() public {
        lptoken.mint(holder1, 1 ether);

        uint256 amount = 1 ether;
        uint64 nmonths = 8;

        vm.prank(holder1);
        stakingcontract.newStake(amount, nmonths);

        assertEq(vinciToken.balanceOf(holder1), 0);

        VinciLPStaking.Stake memory stake = stakingcontract.readStake(holder1, 0);
        assertEq(stake.amount, amount);
        assertEq(stake.releaseTime, block.timestamp + nmonths * 30 days);
        assertEq(stake.monthsLocked, nmonths);
        assert(!stake.withdrawn);
    }

    function testWithdrawWithoutFunds() public {
        lptoken.mint(holder1, 1 ether);

        uint256 amount = 1 ether;
        uint64 nmonths = 8;

        vm.prank(holder1);
        stakingcontract.newStake(amount, nmonths);
        assertEq(lptoken.balanceOf(holder1), 0);

        skip(nmonths * 30 days + 10);

        vm.prank(holder1);
        stakingcontract.withdrawStake(0);

        VinciLPStaking.Stake memory stake = stakingcontract.readStake(holder1, 0);
        assertEq(lptoken.balanceOf(holder1), amount);

        assertEq(stake.amount, amount);
        assertEq(stake.monthsLocked, nmonths);
        assert(stake.withdrawn);
    }

    function testRevertingAPRDistributionNoFunds() public {
        lptoken.mint(holder1, 1 ether);

        uint256 amount = 1 ether;
        uint64 nmonths = 8;

        vm.prank(holder1);
        stakingcontract.newStake(amount, nmonths);

        vm.expectRevert(VinciLPStaking.InsufficientVinciInLPStakingContract.selector);
        stakingcontract.distributeWeeklyAPR();
    }

    function testInstantPayoutWithoutFundsEvents() public {
        lptoken.mint(holder1, 10 ether);

        uint256 amount = 1 ether;
        uint64 nmonths = 12;

        vm.prank(holder1);
        vm.expectEmit(true, false, false, true);
        emit InstantPayoutInVinci(holder1, 0);
        stakingcontract.newStake(amount, nmonths);

        uint256 expectedPayout = 125000000000000;
        vm.prank(holder1);
        vm.expectEmit(true, false, false, true);
        // missed payout is basically the entire payout
        emit InsufficientVinciForInstantPayout(holder1, expectedPayout, expectedPayout);
        stakingcontract.newStake(amount, nmonths);
    }
}
