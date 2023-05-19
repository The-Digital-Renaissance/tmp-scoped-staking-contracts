// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// UNSTAKE AND WITHDRAWALS TESTS
// withdraw is not allowed before release period passes
// withdraw updates contract and user balances
// withdraw with nothing to withdraw (after just withdrawing)
// withdraw is allowed without rewards funds in the contract
// test independence between claiming and unstaking

contract TestUnstakeWithdrawals is BaseTestFunded {
    event UnstakingCompleted(address indexed user, uint256 amount);

    uint256 stakeAmount = 1000 ether;

    function setUp() public override {
        super.setUp();
        vinciToken.mint(user, stakeAmount);
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();
    }

    function testWithdrawBeforeReleasePeriod() public {
        vm.startPrank(user);
        vinciStaking.unstake(stakeAmount / 2);

        assertEq(vinciStaking.currentlyUnstakingBalance(user), stakeAmount / 2);
        skip(1 days);

        vm.expectRevert(VinciStakingV1.UnstakedAmountNotReleasedYet.selector);
        vinciStaking.withdraw();

        // after enough time, withdrawing should be possible
        skip(15 days);
        vinciStaking.withdraw();
    }

    function testWithdrawBalancesUpdated() public {
        uint256 unstakeAmount = stakeAmount / 2;
        vm.startPrank(user);
        vinciStaking.unstake(unstakeAmount);
        skip(15 days);

        uint256 contractBefore = vinciToken.balanceOf(address(vinciStaking));
        uint256 userBefore = vinciToken.balanceOf(user);

        vinciStaking.withdraw();

        assertEq(vinciToken.balanceOf(address(vinciStaking)), contractBefore - unstakeAmount);
        assertEq(vinciToken.balanceOf(user), userBefore + unstakeAmount);
    }

    function testWithdrawAfterJustWithdrawing() public {
        vm.startPrank(user);
        vinciStaking.unstake(stakeAmount / 2);
        skip(15 days);

        vinciStaking.withdraw();

        vm.expectRevert(VinciStakingV1.NothingToWithdraw.selector);
        vinciStaking.withdraw();
    }

    function testIndependenceBetweenClaimAndWithdraw() public {
        vm.startPrank(user);
        skip(6 * 30 days + 1 days);

        vinciStaking.crossCheckpoint();

        skip(30 days);

        uint256 unstakeAmount = 100 ether;
        vinciStaking.unstake(unstakeAmount);
        assertEq(vinciStaking.activeStaking(user), stakeAmount - unstakeAmount);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), unstakeAmount);

        skip(15 days);

        uint256 claimable = vinciStaking.claimableBalance(user);
        vinciStaking.withdraw();
        assertEq(vinciStaking.activeStaking(user), stakeAmount - unstakeAmount);
        assertEq(vinciStaking.claimableBalance(user), claimable);
        assertEq(vinciStaking.currentlyUnstakingBalance(user), 0);
        vm.stopPrank();
    }

    function testUnstakeCompletedEventWithClaim() public {
        uint256 amount = 1000 ether;
        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(amount);

        skip(10 days);

        uint256 unstakeAmount = 500 ether;
        vinciStaking.unstake(unstakeAmount);

        skip(15 days);

        vm.expectEmit(true, false, false, true);
        emit UnstakingCompleted(user, unstakeAmount);
        vinciStaking.withdraw();

        vm.stopPrank();
    }
}
