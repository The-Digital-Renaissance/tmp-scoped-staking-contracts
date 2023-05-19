// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "@libs/libAddressSet.sol";
import "contracts/vinciToken.sol";

contract HandlerVinciToken is Test {
    using LibAddressSet for AddressSet;

    AddressSet internal actors;

    Vinci vinciToken;
    address deployer = 0xfec412C75eA59Fe689C32524362EC116e7996FC0;

    uint256 public freeSupply;
    uint256 public totalSupply;
    uint256 public totalUnvested;
    uint256 public totalBurned;
    uint256 public totalWithdrawn;
    uint256 public totalClaimed;
    mapping(address => uint256) public totalUnvestedOf;

    function reduceActors(function(address) external view returns (uint256) func) public view returns (uint256) {
        return actors.reduce(func);
    }

    function forAllActors(function(address) external returns (bool) func) external returns (bool) {
        return actors.forEach(func);
    }

    function countActors() public view returns (uint256) {
        return actors.count();
    }

    constructor(Vinci _vincitoken) {
        vinciToken = _vincitoken;
        totalSupply = vinciToken.totalSupply();
        freeSupply = totalSupply;
    }

    function setVestings(address to, uint256 amount, uint256 startIndex, uint256 endIndex) public {
        if (amount % 10 == 0) {
            actors.add(to);
        } else {
            to = actors.rand(startIndex);
        }

        if (to == address(0)) return;

        console.log("entering setVestings");
        amount = bound(amount, 1, 1_000_000 ether);
        startIndex = bound(startIndex, 0, 5);
        endIndex = bound(endIndex, startIndex + 1, 6);
        uint256 nvestings = endIndex - startIndex;

        console.log("preparing Timelocks");
        Vinci.TimeLock[] memory templateLocks = new Vinci.TimeLock[](6);
        templateLocks[0] = Vinci.TimeLock(uint160(1 * amount), uint64(block.timestamp + 1 days), false);
        templateLocks[1] = Vinci.TimeLock(uint160(2 * amount), uint64(block.timestamp + 30 days), false);
        templateLocks[2] = Vinci.TimeLock(uint160(3 * amount), uint64(block.timestamp + 60 days), false);
        templateLocks[3] = Vinci.TimeLock(uint160(3 * amount), uint64(block.timestamp + 61 days), false);
        templateLocks[4] = Vinci.TimeLock(uint160(4 * amount), uint64(block.timestamp + 81 days), false);
        templateLocks[5] = Vinci.TimeLock(uint160(5 * amount), uint64(block.timestamp + 11 days), false);

        console.log("looping Timelocks");
        uint256 lockedAmount = 0;
        Vinci.TimeLock[] memory timelocks = new Vinci.TimeLock[](nvestings);
        for (uint256 i = 0; i < nvestings; i++) {
            timelocks[i] = templateLocks[startIndex + i];
            lockedAmount += timelocks[i].amount;
        }

        console.log("checking freeSupply");
        if (lockedAmount > vinciToken.freeSupply()) return;

        console.log("modifying freeSupply");
        freeSupply -= lockedAmount;
        console.log("freeSupply updated");

        vm.prank(deployer);
        vinciToken.setVestingSchedule(to, timelocks);
        totalUnvested += lockedAmount;
        totalUnvestedOf[to] += lockedAmount;
    }

    function withdraw(address to, uint256 amount) public {
        uint256 balanceBefore = vinciToken.balanceOf(to);

        if (amount > vinciToken.freeSupply()) return;

        vm.prank(deployer);
        vinciToken.withdraw(to, amount);

        assertEq(vinciToken.balanceOf(to), balanceBefore + amount);

        totalWithdrawn += amount;
        freeSupply -= amount;
    }

    function claim(uint256 actorSeed) public {
        address actor = actors.rand(actorSeed);

        uint256 vested = vinciToken.getTotalVestedTokens(actor);
        uint256 claimed = vinciToken.getTotalClaimedTokens(actor);
        uint256 claimable = vested - claimed;
        if (claimable == 0) return;

        uint256 balanceBefore = vinciToken.balanceOf(actor);

        vm.prank(actor);
        vinciToken.claim();

        assertEq(vinciToken.balanceOf(actor), balanceBefore + claimable);

        totalClaimed += claimable;
    }

    function burn(uint256 amount, uint256 actorSeed) public {
        address actor = actors.rand(actorSeed);
        if (actor == address(0)) return;

        amount = bound(amount, 0, vinciToken.balanceOf(actor));

        vm.prank(actor);
        vinciToken.burn(amount);

        totalSupply -= amount;
        totalBurned += amount;
    }

    function skipTime(uint256 time) public {
        time = bound(time, 1, 15 days);
        skip(time);
    }

    function unclaimedTokens(address user) public view returns (uint256) {
        // this returns the unclaimed including the unvested tokens and the vested ones
        return vinciToken.getTotalUnvestedTokens(user) - vinciToken.getTotalClaimedTokens(user);
    }
}
