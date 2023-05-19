// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

contract BatchStakingTests is BaseTestNotFunded {
    event Staked(address indexed user, uint256 amount);

    function testSimpleBatchStaking() public {
        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        address[] memory users = _createUsers();
        uint256[] memory amounts = _createAmounts();
        vinciStaking.batchStakeTo(users, amounts);
        vm.stopPrank();

        assertEq(vinciStaking.activeStaking(users[0]), amounts[0]);
        assertEq(vinciStaking.activeStaking(users[1]), amounts[1]);
        assertEq(vinciStaking.activeStaking(users[2]), amounts[2]);
        assertEq(vinciStaking.activeStaking(users[3]), amounts[3]);
    }

    function testDuplicatedBatchStaking() public {
        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        address[] memory users = _createUsers();
        uint256[] memory amounts = _createAmounts();

        vinciStaking.batchStakeTo(users, amounts);
        vinciStaking.batchStakeTo(users, amounts);
        vm.stopPrank();

        assertEq(vinciStaking.activeStaking(users[0]), 2 * amounts[0]);
        assertEq(vinciStaking.activeStaking(users[1]), 2 * amounts[1]);
        assertEq(vinciStaking.activeStaking(users[2]), 2 * amounts[2]);
        assertEq(vinciStaking.activeStaking(users[3]), 2 * amounts[3]);
    }

    function testBatchStakingWithInsufficientFunds() public {
        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        uint256 balance = vinciToken.balanceOf(funder);

        address[] memory users = _createUsers();
        uint256[] memory amounts = _createAmounts();
        // increase the last amount so that the total funds are higher than funder's balance
        amounts[3] = balance;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vinciStaking.batchStakeTo(users, amounts);
        vm.stopPrank();
    }

    function testBatchStakingEvents() public {
        vm.startPrank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        address[] memory users = _createUsers();
        uint256[] memory amounts = _createAmounts();
        // increase the last amount so that the total funds are higher than funder's balance

        for (uint256 i = 0; i < users.length; i++) {
            vm.expectEmit(true, false, false, true);
            emit Staked(users[i], amounts[i]);
        }
        vinciStaking.batchStakeTo(users, amounts);
    }
}
