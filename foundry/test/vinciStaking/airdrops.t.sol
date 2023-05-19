// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

contract FundedAirdropsTests is BaseTestFunded {
    function testAirdropToNonStakers() public {
        address[] memory users = _createUsers();
        uint256[] memory airdropAmounts = _createAmounts();

        vm.startPrank(funder);
        deal(address(vinciToken), funder, 100000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        vm.expectRevert("Users must have active stake to receive airdrops");
        vinciStaking.batchAirdrop(users, airdropAmounts);
    }

    function testAirdropFromWallet() public {
        address[] memory users = _createUsers();
        uint256[] memory airdropAmounts = _createAmounts();
        uint256[] memory stakeAmounts = _createSmallAmonts();

        vm.startPrank(funder);
        deal(address(vinciToken), funder, 100000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        // this batch stake is needed to create the users
        vinciStaking.batchStakeTo(users, stakeAmounts);

        uint256 contractBalanceBefore = vinciToken.balanceOf(address(vinciStaking));
        uint256 totalAirdroped = airdropAmounts[0] + airdropAmounts[1] + airdropAmounts[2] + airdropAmounts[3];
        uint256 balanceBefore = vinciToken.balanceOf(funder);

        vinciStaking.batchAirdrop(users, airdropAmounts);

        assertEq(vinciToken.balanceOf(funder), balanceBefore - totalAirdroped);
        assertEq(vinciToken.balanceOf(address(vinciStaking)), contractBalanceBefore + totalAirdroped);

        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[0]), airdropAmounts[0]);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[1]), airdropAmounts[1]);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[2]), airdropAmounts[2]);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[3]), airdropAmounts[3]);

        assertEq(vinciStaking.getTotalUnclaimableBalance(users[0]), airdropAmounts[0]);
        assertEq(vinciStaking.getTotalUnclaimableBalance(users[1]), airdropAmounts[1]);
        assertEq(vinciStaking.getTotalUnclaimableBalance(users[2]), airdropAmounts[2]);
        assertEq(vinciStaking.getTotalUnclaimableBalance(users[3]), airdropAmounts[3]);

        vm.stopPrank();
    }

    function testClaimAirdropOfNonExistingUser() public {
        address[] memory users = _createUsers();
        uint256[] memory airdropAmounts = _createAmounts();
        uint256[] memory stakeAmounts = _createSmallAmonts();

        vm.startPrank(funder);
        deal(address(vinciToken), funder, 100000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        // this batch stake is needed to create the users
        vinciStaking.batchStakeTo(users, stakeAmounts);

        vinciStaking.batchAirdrop(users, airdropAmounts);
        vm.stopPrank();

        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[0]), airdropAmounts[0]);
        assertEq(vinciStaking.getTotalUnclaimableBalance(users[0]), airdropAmounts[0]);
        assertEq(vinciStaking.claimableBalance(users[0]), 0);

        skip(7 * 30 days);
        vm.prank(users[0]);
        vinciStaking.crossCheckpoint();

        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[0]), 0);
        assertEq(vinciStaking.getTotalUnclaimableBalance(users[0]), 0);
        uint256 claimable = vinciStaking.claimableBalance(users[0]);
        assertEq(claimable, airdropAmounts[0]);

        uint256 balanceBefore = vinciToken.balanceOf(users[0]);
        vm.prank(users[0]);
        vinciStaking.claim();
        assertEq(vinciToken.balanceOf(users[0]), balanceBefore + claimable);
    }

    function testAirdropFromWalletNotEnoughBalance() public {
        address[] memory users = _createUsers();
        uint256[] memory airdropAmounts = _createAmounts();
        uint256[] memory stakeAmounts = _createSmallAmonts();

        vm.startPrank(funder);
        // user will have some funds, but definitely not enough to airdrop to all users
        deal(address(vinciToken), funder, 10 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.batchStakeTo(users, stakeAmounts);

        uint256 contractBalanceBefore = vinciToken.balanceOf(address(vinciStaking));
        uint256 totalAirdroped = airdropAmounts[0] + airdropAmounts[1] + airdropAmounts[2] + airdropAmounts[3];
        uint256 aidropperBalanceBefore = vinciToken.balanceOf(funder);
        // lets make sure the funder does not have enough to airdrop
        assertGt(totalAirdroped, aidropperBalanceBefore);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vinciStaking.batchAirdrop(users, airdropAmounts);

        // lets make sure no transfers actually happened
        assertEq(vinciToken.balanceOf(funder), aidropperBalanceBefore);
        assertEq(vinciToken.balanceOf(address(vinciStaking)), contractBalanceBefore);
        // and of course no airdrop happened either
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[0]), 0);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[1]), 0);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[2]), 0);
        assertEq(vinciStaking.getUnclaimableFromAirdrops(users[3]), 0);

        vm.stopPrank();
    }

    // handy function to test batch staking
    function _createSmallAmonts() internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;
        return amounts;
    }
}
