// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract TestLPStakes is BaseLPTestFunded {
    function testWrongNumberOfMonths(uint64 nMonths) public {
        nMonths = nMonths % 24;

        lptoken.mint(holder1, 1 ether);

        if ((nMonths != 4) && (nMonths != 8) && (nMonths != 12)) {
            vm.expectRevert(VinciLPStaking.UnsupportedNumberOfMonths.selector);
        }
        vm.prank(holder1);
        stakingcontract.newStake(1 ether, nMonths);
    }

    //    function testInvalidAmount() public {
    //        lptoken.mint(holder1, 1 ether);
    //        vm.expectRevert(VinciLPStaking.InvalidAmount.selector);
    //        vm.prank(holder1);
    //        stakingcontract.newStake(0, 4);
    //    }

    function testStakeInfo() public {
        lptoken.mint(holder1, 1 ether);
        vm.prank(holder1);

        uint256 amount = 0.5 ether;
        uint64 nMonths = 8;

        uint128 stakeTime = uint64(block.timestamp);
        stakingcontract.newStake(amount, nMonths);

        VinciLPStaking.Stake memory stake = stakingcontract.readStake(holder1, 0);

        assertEq(stake.releaseTime, stakeTime + (nMonths * 30 days));
        assertEq(stake.monthsLocked, nMonths);
        assertEq(stake.amount, amount);
    }

    function testInstantPayout() public {
        // 1 LP is equivalent to 2 vinci
        uint256 LPpriceInVinci = 20;
        uint256 _newPrice = LPpriceInVinci * (10 ** vinciToken.decimals());
        stakingcontract.setLPPriceInVinci(_newPrice);

        uint256 stakeAmount = 1000 ether;
        lptoken.mint(holder1, stakeAmount);
        lptoken.mint(holder2, stakeAmount);
        lptoken.mint(holder3, stakeAmount);
        vm.prank(holder1);
        lptoken.approve(address(stakingcontract), stakeAmount);
        vm.prank(holder2);
        lptoken.approve(address(stakingcontract), stakeAmount);
        vm.prank(holder3);
        lptoken.approve(address(stakingcontract), stakeAmount);

        // instant payout of 4 months
        uint256 balanceBefore = vinciToken.balanceOf(holder1);
        vm.prank(holder1);
        stakingcontract.newStake(stakeAmount, 4);
        uint256 expectedPayout = stakeAmount * LPpriceInVinci * 50 / 10000;
        assertEq(vinciToken.balanceOf(holder1), balanceBefore + expectedPayout);

        // instant payout of 4 months
        balanceBefore = vinciToken.balanceOf(holder2);
        vm.prank(holder2);
        stakingcontract.newStake(stakeAmount, 8);
        expectedPayout = stakeAmount * LPpriceInVinci * 150 / 10000;
        assertEq(vinciToken.balanceOf(holder2), balanceBefore + expectedPayout);

        // instant payout of 4 months
        balanceBefore = vinciToken.balanceOf(holder3);
        vm.prank(holder3);
        stakingcontract.newStake(stakeAmount, 12);
        expectedPayout = stakeAmount * LPpriceInVinci * 500 / 10000;
        assertEq(vinciToken.balanceOf(holder3), balanceBefore + expectedPayout);
    }

    function testInstantPayoutHardcodedValues() public {
        // 1 LP is equivalent to 2 vinci
        uint256 LPpriceInVinci = 2;
        uint256 _newPrice = LPpriceInVinci * (10 ** vinciToken.decimals());
        stakingcontract.setLPPriceInVinci(_newPrice);

        uint256 stakeAmount = 500 ether;
        lptoken.mint(holder1, stakeAmount);
        lptoken.mint(holder2, stakeAmount);
        lptoken.mint(holder3, stakeAmount);
        vm.prank(holder1);
        lptoken.approve(address(stakingcontract), stakeAmount);
        vm.prank(holder2);
        lptoken.approve(address(stakingcontract), stakeAmount);
        vm.prank(holder3);
        lptoken.approve(address(stakingcontract), stakeAmount);

        // instant payout of 4 months
        uint256 balanceBefore = vinciToken.balanceOf(holder1);
        vm.prank(holder1);
        stakingcontract.newStake(stakeAmount, 12);
        uint256 expectedPayout = 50 ether;
        assertEq(vinciToken.balanceOf(holder1), balanceBefore + expectedPayout);

        // instant payout of 4 months
        balanceBefore = vinciToken.balanceOf(holder2);
        vm.prank(holder2);
        stakingcontract.newStake(stakeAmount, 8);
        expectedPayout = stakeAmount * LPpriceInVinci * 150 / 10000;
        assertEq(vinciToken.balanceOf(holder2), balanceBefore + expectedPayout);

        // instant payout of 4 months
        balanceBefore = vinciToken.balanceOf(holder3);
        vm.prank(holder3);
        stakingcontract.newStake(stakeAmount, 12);
        expectedPayout = stakeAmount * LPpriceInVinci * 500 / 10000;
        assertEq(vinciToken.balanceOf(holder3), balanceBefore + expectedPayout);
    }
}
