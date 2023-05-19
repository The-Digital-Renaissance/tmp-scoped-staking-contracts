// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/vinciToken.sol";
import {BaseVinciToken} from "./baseToken.t.sol";

contract TestVinciTokenVestings is BaseVinciToken {
    function testVestingsSetup() public {
        assertEq(vinci.getNumberOfTimelocks(user1), 0);
    }

    function testSetVestingSchedule() public {
        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](12);
        timeLocks[0] = Vinci.TimeLock(1000, uint64(block.timestamp + 1 days), false);
        timeLocks[1] = Vinci.TimeLock(2000, uint64(block.timestamp + 30 days), false);
        timeLocks[2] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[3] = Vinci.TimeLock(3000, uint64(block.timestamp + 61 days), false);
        timeLocks[4] = Vinci.TimeLock(3000, uint64(block.timestamp + 62 days), false);
        timeLocks[5] = Vinci.TimeLock(3000, uint64(block.timestamp + 63 days), false);
        timeLocks[6] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[7] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[8] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[9] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[10] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[11] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);

        vinci.setVestingSchedule(user1, timeLocks);

        assertEq(vinci.getNumberOfTimelocks(user1), 12);

        Vinci.TimeLock memory firstTimelock = vinci.readTimelock(user1, 0);
        assertEq(firstTimelock.amount, 1000);
        assertEq(firstTimelock.releaseTime, block.timestamp + 1 days);

        Vinci.TimeLock memory secondTimelock = vinci.readTimelock(user1, 1);
        assertEq(secondTimelock.amount, 2000);
        assertEq(secondTimelock.releaseTime, block.timestamp + 30 days);
    }

    function testTotalSupply() public {
        uint256 totalSupply = vinci.totalSupply();

        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](12);
        timeLocks[0] = Vinci.TimeLock(1000, uint64(block.timestamp + 1 days), false);
        timeLocks[1] = Vinci.TimeLock(2000, uint64(block.timestamp + 30 days), false);
        timeLocks[2] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[3] = Vinci.TimeLock(3000, uint64(block.timestamp + 61 days), false);
        timeLocks[4] = Vinci.TimeLock(3000, uint64(block.timestamp + 62 days), false);
        timeLocks[5] = Vinci.TimeLock(3000, uint64(block.timestamp + 63 days), false);
        timeLocks[6] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[7] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[8] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[9] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[10] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[11] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);

        vinci.setVestingSchedule(user1, timeLocks);

        assertEq(vinci.totalSupply(), totalSupply);
    }

    function testSetMultipleVestingsForSameUser() public {
        assertEq(vinci.getNumberOfTimelocks(user2), 0);

        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](12);
        timeLocks[0] = Vinci.TimeLock(1000, uint64(block.timestamp + 1 days), false);
        timeLocks[1] = Vinci.TimeLock(2000, uint64(block.timestamp + 30 days), false);
        timeLocks[2] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[3] = Vinci.TimeLock(3000, uint64(block.timestamp + 61 days), false);
        timeLocks[4] = Vinci.TimeLock(3000, uint64(block.timestamp + 62 days), false);
        timeLocks[5] = Vinci.TimeLock(3000, uint64(block.timestamp + 63 days), false);
        timeLocks[6] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[7] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[8] = Vinci.TimeLock(3000, uint64(block.timestamp + 64 days), false);
        timeLocks[9] = Vinci.TimeLock(3000, uint64(block.timestamp + 65 days), false);
        timeLocks[10] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);
        timeLocks[11] = Vinci.TimeLock(3000, uint64(block.timestamp + 60 days), false);

        vinci.setVestingSchedule(user2, timeLocks);

        assertEq(vinci.getNumberOfTimelocks(user2), 12);

        Vinci.TimeLock[] memory timeLocks2 = new Vinci.TimeLock[](6);
        timeLocks2[0] = Vinci.TimeLock(1010, uint64(block.timestamp + 1 days), false);
        timeLocks2[1] = Vinci.TimeLock(2010, uint64(block.timestamp + 30 days), false);
        timeLocks2[2] = Vinci.TimeLock(3010, uint64(block.timestamp + 60 days), false);
        timeLocks2[3] = Vinci.TimeLock(3010, uint64(block.timestamp + 61 days), false);
        timeLocks2[4] = Vinci.TimeLock(3010, uint64(block.timestamp + 62 days), false);
        timeLocks2[5] = Vinci.TimeLock(3010, uint64(block.timestamp + 63 days), false);

        vinci.setVestingSchedule(user2, timeLocks2);
        assertEq(vinci.getNumberOfTimelocks(user2), 18);

        Vinci.TimeLock memory timelock = vinci.readTimelock(user2, 12);
        assertEq(timelock.amount, 1010);
    }
}
