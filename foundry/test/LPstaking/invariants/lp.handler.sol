// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../../../contracts/LPstaking.sol";
import "../../../../contracts/mocks/vinciLPToken.sol";
import "../../../../contracts/mocks/vinciToken.sol";
import "@forge/src/Test.sol";
import "@libs/libAddressSet.sol";

contract HandlerLPstaking is Test {
    using LibAddressSet for AddressSet;

    AddressSet internal actors;

    VinciMockToken vincitoken;
    VinciMockLPToken lptoken;
    VinciLPStaking lpstaking;

    uint256 public totalTimeSkipped;
    uint256 public totalLPMinted;
    uint256 public totalVinciMinted;
    uint256 public totalStaked;
    uint256 public totalWithdrawn;
    uint256 public totalClaimed;
    uint256 public numberOfAPRDistributions;
    uint256 public lastAPRdistribution;
    uint256 public instantPayouts;

    uint256 public time;

    event APRDistributed(uint256 timestamp);

    function reduceActors(function(address) external view returns (uint256) func) public view returns (uint256) {
        return actors.reduce(func);
    }

    function forAllActors(function(address) external returns (bool) func) external returns (bool) {
        return actors.forEach(func);
    }

    modifier moveTime() {
        time += 1 days;
        vm.warp(time);
        _;
    }

    constructor(VinciMockToken _vincitoken, VinciMockLPToken _lptoken, VinciLPStaking _lpstaking) {
        vincitoken = _vincitoken;
        lptoken = _lptoken;
        lpstaking = _lpstaking;
    }

    function stake(address staker, uint256 amount, uint64 nmonths) external moveTime {
        if (staker == address(0)) return;

        actors.add(staker);

        amount = bound(amount, 0, 100_000_000_000_000 ether);

        nmonths = uint64((nmonths % 3 + 1) * 4);
        if ((nmonths != 4) && (nmonths != 8) && (nmonths != 12)) {
            vm.expectRevert(VinciLPStaking.UnsupportedNumberOfMonths.selector);
            vm.prank(staker);
            lpstaking.newStake(amount, nmonths);
            return;
        }
        if (amount == 0) {
            vm.expectRevert(VinciLPStaking.InvalidAmount.selector);
            vm.prank(staker);
            lpstaking.newStake(amount, nmonths);
            return;
        }

        lptoken.mint(staker, amount);
        totalLPMinted += amount;

        vm.prank(staker);
        lptoken.approve(address(lpstaking), amount);

        uint256 balanceBefore = vincitoken.balanceOf(staker);
        vm.prank(staker);
        lpstaking.newStake(amount, nmonths);

        instantPayouts += vincitoken.balanceOf(staker) - balanceBefore;
        totalStaked += amount;
    }

    function withdraw(uint256 actorSeed, uint256 randIndex) external moveTime {
        address user = actors.rand(actorSeed);

        uint256 nstakes = lpstaking.getNumberOfStakes(user);
        if (nstakes == 0) return;

        uint256 stakeIndex = bound(randIndex, 0, nstakes - 1);
        uint128 withdrawTime = lpstaking.getStakeReleaseTime(user, stakeIndex);
        uint256 withdrawAmount = lpstaking.getStakeAmount(user, stakeIndex);
        uint256 balanceBefore = lptoken.balanceOf(user);

        if (block.timestamp < withdrawTime) {
            vm.expectRevert(VinciLPStaking.StakeNotReleased.selector);
            vm.prank(user);
            lpstaking.withdrawStake(stakeIndex);
            return;
        }

        if (withdrawAmount == 0) {
            vm.expectRevert(VinciLPStaking.AlreadyWithdrawnIndex.selector);
            vm.prank(user);
            lpstaking.withdrawStake(stakeIndex);
            return;
        }

        if (lpstaking.isWithdrawn(user, stakeIndex)) {
            vm.expectRevert(VinciLPStaking.AlreadyWithdrawnIndex.selector);
            vm.prank(user);
            lpstaking.withdrawStake(stakeIndex);
            return;
        }

        uint256 claimable = lpstaking.readCurrentClaimable(user, stakeIndex);

        vm.prank(user);
        lpstaking.withdrawStake(stakeIndex);

        totalClaimed += claimable;
        totalWithdrawn += withdrawAmount;

        assertEq(lptoken.balanceOf(user), balanceBefore + withdrawAmount, "wrong balance after withdraw");
    }

    function distributeAPR() external moveTime {
        // if there are no LPtokens, the staking contract will revert
        if (lptoken.balanceOf(address(lpstaking)) == 0) return;
        // this is to cover the very beginning of the period
        if (lastAPRdistribution + 1 weeks + 10 > block.timestamp) return;

        if (lpstaking.fundsForStakingRewards() < lpstaking.WEEKLY_VINCI_REWARDS()) {
            vm.expectRevert(VinciLPStaking.InsufficientVinciInLPStakingContract.selector);
            lpstaking.distributeWeeklyAPR();
            return;
        }

        lpstaking.distributeWeeklyAPR();
        numberOfAPRDistributions += 1;
        lastAPRdistribution = block.timestamp;
        emit APRDistributed(block.timestamp);
    }

    function claimRewards(uint256 actorSeed, uint256 stakeIndexSeed) public moveTime {
        address user = actors.rand(actorSeed);

        uint256 n = lpstaking.getNumberOfStakes(user);
        if (n == 0) return;

        uint256 stakeIndex = stakeIndexSeed % n;

        uint256 claimableBefore = lpstaking.readCurrentClaimable(user, stakeIndex);
        if (claimableBefore == 0) return;

        bool shouldGetFullRewards = claimableBefore <= lpstaking.fundsForStakingRewards();

        uint256 balanceBefore = vincitoken.balanceOf(user);
        vm.prank(user);
        lpstaking.claimRewards(stakeIndex);
        uint256 balanceAfter = vincitoken.balanceOf(user);
        uint256 effectiveClaim = balanceAfter - balanceBefore;

        if (shouldGetFullRewards) {
            assertEq(effectiveClaim, claimableBefore, "full claim didnt happen");
        }

        totalClaimed += effectiveClaim;
    }

    function addToTotalVinciMinted(uint256 amount) public {
        totalVinciMinted += amount;
    }
}
