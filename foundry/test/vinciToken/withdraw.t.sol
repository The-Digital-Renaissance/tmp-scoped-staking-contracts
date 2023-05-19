// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/vinciToken.sol";
import {BaseVinciToken} from "./baseToken.t.sol";

contract BaseVinciTokenWithVestings is BaseVinciToken {
    uint256 totalVested;

    function setUp() public override {
        super.setUp();

        Vinci.TimeLock[] memory timeLocks = new Vinci.TimeLock[](12);
        timeLocks[0] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 1 days), false);
        timeLocks[1] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 30 days), false);
        timeLocks[2] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 60 days), false);
        timeLocks[3] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 61 days), false);
        timeLocks[4] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 62 days), false);
        timeLocks[5] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 63 days), false);
        timeLocks[6] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 64 days), false);
        timeLocks[7] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 65 days), false);
        timeLocks[8] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 64 days), false);
        timeLocks[9] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 65 days), false);
        timeLocks[10] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 60 days), false);
        timeLocks[11] = Vinci.TimeLock(1000 ether, uint64(block.timestamp + 60 days), false);
        totalVested = 12000 ether;
        vinci.setVestingSchedule(user1, timeLocks);
    }
}

contract TestVinciTokenVestings is BaseVinciTokenWithVestings {
    function testFreeSupplyAfterVestings() public {
        assertEq(vinci.freeSupply(), vinci.totalSupply() - totalVested);
    }

    function testWithdrawMoreThanFreeSupply() public {
        uint256 freeSupply = vinci.freeSupply();

        vm.expectRevert("amount exceeds free supply");
        vinci.withdraw(user1, freeSupply + 1);
    }
}
