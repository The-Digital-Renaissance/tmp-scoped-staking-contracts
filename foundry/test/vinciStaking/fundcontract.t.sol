// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// CONTRACT FUNDING TESTS ///
// vinci balance reduced in funder
// contract balance incresed
// rewards fund increased
// cannot fund without enough balance
// two fundings double the funds balance
// funding event
// funds removed event
// remove funds, and rewards fund updated
// cannot remove more funds than initial funds
// cannot remove funds that have been allocated
// cannot remove funds that have been allocated, but yes after unstaking (and being penalized)

contract TestFundingStakingContract is BaseTestNotFunded {
    event StakingRewardsFunded(address indexed funder, uint256 amount);
    event NonAllocatedStakingRewardsFundsRetrieved(address indexed funder, uint256 amount);

    function testContractSetup() public {
        // there should be no Vinci in the contract at all
        assertEq(vinciToken.balanceOf(address(vinciStaking)), 0);
        assertEq(vinciStaking.vinciStakingRewardsFunds(), 0);
        assertGt(vinciToken.balanceOf(funder), 0);
    }

    function testFundWithMoreVinciThanOwned() public {
        uint256 funderBalance = vinciToken.balanceOf(funder);

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vinciStaking.fundContractWithVinciForRewards(2 * funderBalance);
        vm.stopPrank();

        assertEq(vinciToken.balanceOf(address(vinciStaking)), 0);
        assertEq(vinciStaking.vinciStakingRewardsFunds(), 0);
    }

    function testSuccessfulFunding() public {
        uint256 funderBalance = vinciToken.balanceOf(funder);

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vinciStaking.fundContractWithVinciForRewards(funderBalance / 2);
        vm.stopPrank();

        assertEq(vinciToken.balanceOf(address(vinciStaking)), funderBalance / 2);
        assertEq(vinciStaking.vinciStakingRewardsFunds(), funderBalance / 2);
        assertEq(vinciToken.balanceOf(funder), funderBalance / 2);
    }

    function testSuccessfulDoubleFunding() public {
        uint256 fundAmount = vinciToken.balanceOf(funder) / 2;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vm.stopPrank();

        assertEq(vinciToken.balanceOf(address(vinciStaking)), 2 * fundAmount);
        assertEq(vinciStaking.vinciStakingRewardsFunds(), 2 * fundAmount);
    }

    function testFundingEvent() public {
        uint256 fundAmount = 1000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vm.expectEmit(false, false, false, true);
        emit StakingRewardsFunded(funder, fundAmount);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);

        vm.stopPrank();
    }

    function testRemoveStakedRewardsFundsBalances() public {
        uint256 fundAmount = 1000_000_000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);

        uint256 funderBalanceBefore = vinciToken.balanceOf(funder);
        uint256 contractBalanceBefore = vinciToken.balanceOf(address(vinciStaking));
        uint256 removeAmount = 500_000_000 ether;
        vinciStaking.removeNonAllocatedStakingRewards(removeAmount);

        assertEq(vinciStaking.vinciStakingRewardsFunds(), fundAmount - removeAmount);
        assertEq(vinciToken.balanceOf(funder), funderBalanceBefore + removeAmount);
        assertEq(vinciToken.balanceOf(address(vinciStaking)), contractBalanceBefore - removeAmount);
    }

    function testRemoveStakedRewardsFundsEvent() public {
        uint256 fundAmount = 1000_000_000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);

        uint256 removeAmount = 500_000_000 ether;
        vm.expectEmit(true, false, false, true);
        emit NonAllocatedStakingRewardsFundsRetrieved(funder, removeAmount);
        vinciStaking.removeNonAllocatedStakingRewards(removeAmount);
    }

    function testCannotRemoveMoreFundsThanInStakingFund() public {
        uint256 fundAmount = 100_000_000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vinciStaking.fundContractWithVinciForRewards(2 * fundAmount);

        uint256 currentFunds = vinciStaking.vinciStakingRewardsFunds();
        uint256 removeAmount = currentFunds + 1;

        vm.expectRevert();
        vinciStaking.removeNonAllocatedStakingRewards(removeAmount);
    }

    function testCannotRemoveAfterRewardsHaveBeenAllocated() public {
        uint256 fundAmount = 1_000_000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vm.stopPrank();

        // stake enough so that the rewards funds is emptied
        uint256 stakeAmount = 200 * fundAmount;
        vm.startPrank(user);
        vinciToken.mint(user, 100 * stakeAmount);
        vinciToken.mint(user, 100 * stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();

        assertEq(vinciStaking.vinciStakingRewardsFunds(), 0);

        vm.prank(funder);
        vm.expectRevert();
        vinciStaking.removeNonAllocatedStakingRewards(1);
    }

    function testCannotRemoveAfterRewardsHaveBeenAllocatedButYesAfterUnstaking() public {
        uint256 fundAmount = 1_000_000 ether;

        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(fundAmount);
        vm.stopPrank();

        // stake enough so that the rewards funds is emptied
        uint256 stakeAmount = 200 * fundAmount;
        vm.startPrank(user);
        vinciToken.mint(user, 100 * stakeAmount);
        vinciToken.mint(user, 100 * stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        skip(30 days);
        vinciStaking.unstake(uint256(stakeAmount / 3));
        vm.stopPrank();
        assertGt(vinciStaking.vinciStakingRewardsFunds(), 0);

        vm.prank(funder);
        vinciStaking.removeNonAllocatedStakingRewards(1);
    }
}
