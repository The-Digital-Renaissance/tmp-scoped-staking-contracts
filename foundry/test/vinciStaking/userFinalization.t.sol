// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./base.t.sol";

/// USER FINALIZATION TESTS
// events firing
// finalize user only if unstake is full amount
// finalization resets tier
// finalization resets checkpoints
// finalizatino and new stake shows reset checkpoint period length
// funalization removes superstaker status

contract BaseUserFinalization is BaseTestFunded {
    event StakeholderFinished(address indexed user);

    uint256 stakeAmount = 20_000_000 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(user);
        vinciToken.mint(user, 10 * stakeAmount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(stakeAmount);
        vm.stopPrank();
    }
}

contract TestUserFinalization is BaseUserFinalization {
    function testFinalizationEvents() public {
        vm.expectEmit(true, false, false, false);
        emit StakeholderFinished(user);
        vm.prank(user);
        vinciStaking.unstake(stakeAmount);
    }

    function testUserFinalizeResetsCheckpoint() public {
        vm.startPrank(user);
        assertGt(vinciStaking.nextCheckpointTimestamp(user), 0);
        vinciStaking.unstake(stakeAmount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), 0);
    }

    function testUserFinalizeResetsTier() public {
        assertGt(stakeAmount, vinciStaking.getTierThreshold(1));

        vm.startPrank(user);
        assertGt(vinciStaking.userTier(user), 0);
        vinciStaking.unstake(stakeAmount);
        assertEq(vinciStaking.userTier(user), 0);
    }

    function testFinalizeOnlyIfFullAmount() public {
        vm.startPrank(user);

        assertGt(vinciStaking.userTier(user), 0);
        uint256 unstakeAmount = vinciStaking.activeStaking(user) / 4;
        assertGt(unstakeAmount, vinciStaking.getTierThreshold(1));

        vinciStaking.unstake(unstakeAmount);
        assertGt(vinciStaking.nextCheckpointTimestamp(user), 0);
        assertGt(vinciStaking.userTier(user), 0);

        vinciStaking.unstake(vinciStaking.activeStaking(user));
        assertEq(vinciStaking.nextCheckpointTimestamp(user), 0);
        assertEq(vinciStaking.userTier(user), 0);
    }

    function testFinalizeAfterMultipleCheckpointCrossResetsMultiplier() public {
        vm.startPrank(user);

        skip(7 * 30 days);
        vinciStaking.crossCheckpoint();
        skip(6 * 30 days);
        vinciStaking.crossCheckpoint();
        skip(5 * 30 days);
        vinciStaking.crossCheckpoint();

        vinciStaking.unstake(stakeAmount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), 0);

        vinciStaking.stake(stakeAmount);
        assertEq(vinciStaking.nextCheckpointTimestamp(user), block.timestamp + 6 * 30 days);
    }

    function testSuperStakerLostAfterFinalization() public {
        skip(7 * 30 days);
        vm.startPrank(user);

        vinciStaking.crossCheckpoint();
        assert(vinciStaking.isSuperstaker(user));

        assertEq(vinciStaking.activeStaking(user), stakeAmount);
        vinciStaking.unstake(stakeAmount);
        assert(!vinciStaking.isSuperstaker(user));
    }
}
