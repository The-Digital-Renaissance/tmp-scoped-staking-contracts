// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/vinciToken.sol";
import {BaseVinciToken} from "./baseToken.t.sol";

contract TestViewAndClaim is BaseVinciToken {
    function testSetVestingSchedule() public {
        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](4);
        timeLocks[0] = Vinci.TimeLock(1000, uint64(block.timestamp + 30 days), false);
        timeLocks[1] = Vinci.TimeLock(2000, uint64(block.timestamp + 60 days), false);
        timeLocks[2] = Vinci.TimeLock(3000, uint64(block.timestamp + 90 days), false);
        timeLocks[3] = Vinci.TimeLock(4000, uint64(block.timestamp + 120 days), false);

        vinci.setVestingSchedule(user1, timeLocks);

        skip(31 days);

        uint256 vested = vinci.getTotalVestedTokens(user1);
        assertEq(vested, 1000);
        assertEq(vinci.getTotalUnvestedTokens(user1), 2000 + 3000 + 4000);

        assertEq(vinci.getTotalVestedTokens(user1), 1000);
        assertEq(vinci.getTotalClaimedTokens(user1), 0);

        vm.prank(user1);
        vinci.claim();
        assertEq(vinci.balanceOf(user1), 1000);
        assertEq(vinci.getTotalVestedTokens(user1), 1000);
        assertEq(vinci.getTotalClaimedTokens(user1), 1000);
        assertEq(vinci.getTotalUnvestedTokens(user1), 2000 + 3000 + 4000);
    }

    function testSetVestingScheduleMultipleVested() public {
        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](4);
        timeLocks[0] = Vinci.TimeLock(1000, uint64(block.timestamp + 30 days), false);
        timeLocks[1] = Vinci.TimeLock(2000, uint64(block.timestamp + 60 days), false);
        timeLocks[2] = Vinci.TimeLock(3000, uint64(block.timestamp + 90 days), false);
        timeLocks[3] = Vinci.TimeLock(4000, uint64(block.timestamp + 120 days), false);

        vinci.setVestingSchedule(user1, timeLocks);

        skip(91 days);

        uint256 vested = vinci.getTotalVestedTokens(user1);
        assertEq(vested, 1000 + 2000 + 3000);
        assertEq(vinci.getTotalUnvestedTokens(user1), 4000);

        vm.prank(user1);
        vinci.claim();
        assertEq(vinci.balanceOf(user1), 1000 + 2000 + 3000);
        assertEq(vinci.getTotalVestedTokens(user1), 6000);
        assertEq(vinci.getTotalUnvestedTokens(user1), 4000);
        assertEq(vinci.getTotalClaimedTokens(user1), 6000);

        uint256 vestedButUnclaimed = vinci.getTotalVestedTokens(user1) - vinci.getTotalClaimedTokens(user1);
        assertEq(vestedButUnclaimed, 0);
    }
}
