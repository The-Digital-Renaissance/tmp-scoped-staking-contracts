// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

//////////// CLAIMS TESTS
// check Claimed events
// when user claims, user balance is increased
// when user claims, contract balance is decreased
// claiming reverts if claimable balance is zero
// user can claim even if there is no active stake anymore (from previous checkpoint period)

contract ClaimsTests is BaseTestFunded {
    event Claimed(address indexed user, uint256 amount);

    function testBasicClaimAndEvent() public {
        uint256 stakeAmount = 1000 ether;
        vinciToken.mint(user, stakeAmount);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(7 * 30 days);
        vinciStaking.crossCheckpoint();

        uint256 claimable = vinciStaking.claimableBalance(user);
        assertGt(claimable, 0);
        assertEq(claimable, _estimateRewards(stakeAmount, 6 * 30 days));

        // make sure all claimable was transfered to the user
        uint256 balanceBefore = vinciToken.balanceOf(user);

        vm.expectEmit(true, false, false, true);
        emit Claimed(user, claimable);
        vinciStaking.claim();

        assertEq(vinciToken.balanceOf(user) - balanceBefore, claimable);
        assertEq(vinciStaking.claimableBalance(user), 0);
        vm.stopPrank();
    }

    function testTwoTimes() public {
        uint256 stakeAmount = 1000 ether;
        vinciToken.mint(user, stakeAmount);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        skip(7 * 30 days);

        vinciStaking.crossCheckpoint();
        vinciStaking.claim();

        vm.expectRevert(VinciStakingV1.NothingToClaim.selector);
        vinciStaking.claim();

        vm.stopPrank();
    }

    function testClaimNonUpdatedCheckpoint() public {
        uint256 stakeAmount = 1000 ether;
        vinciToken.mint(user, stakeAmount);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        skip(7 * 30 days);

        // as checkpoint is not updated, the claimable balance shown should be wrong
        assert(vinciStaking.canCrossCheckpoint(user));
        uint256 claimable = vinciStaking.claimableBalance(user);
        assertEq(claimable, 0);

        vm.expectRevert(VinciStakingV1.NothingToClaim.selector);
        vinciStaking.claim();

        vm.stopPrank();
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

        vm.prank(user);
        vinciStaking.claim();

        // make sure these havent changed
        assertEq(vinciStaking.getUnclaimableFromBaseApr(user), unclaimableFromBaseApr);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(user), unclaimableFromAirdrops);
        assertEq(vinciStaking.getUnclaimableFromPenaltyPot(user), unclaimableFromPenaltyPot);
    }

    function testClaimingOldClaimableWithoutActiveStakeAnymore() public {
        uint256 stakeAmount = 1000 ether;
        vinciToken.mint(user, stakeAmount);

        vm.startPrank(user);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);

        skip(9 * 30 days);
        vinciStaking.crossCheckpoint();
        uint256 claimable = vinciStaking.claimableBalance(user);
        assertGt(claimable, 0);

        // After unstaking, even though current activeStaking is zero, old claimable should still be claimable
        vinciStaking.unstake(1000 ether);
        assertEq(vinciStaking.activeStaking(user), 0);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), 0);
        // claimable balance should be the same
        assertEq(claimable, vinciStaking.claimableBalance(user));

        uint256 balance = vinciToken.balanceOf(user);
        vinciStaking.claim();
        assertEq(vinciToken.balanceOf(user), balance + claimable);
        assertEq(vinciStaking.claimableBalance(user), 0);

        vm.stopPrank();
    }
}
