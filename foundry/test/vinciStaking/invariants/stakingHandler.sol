// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@libs/libAddressSet.sol";

import "@forge/src/Test.sol";
import "@forge/src/StdInvariant.sol";
import "contracts/vinciStaking.sol";
import "contracts/mocks/vinciToken.sol";

contract StakingHandler is Test {
    using LibAddressSet for AddressSet;

    VinciMockToken vinciToken;
    VinciStakingV1 vinciStaking;

    AddressSet internal actors;
    address actor;
    address operator = makeAddr("operator");
    address funder = makeAddr("funder");

    uint256 public totalMinted;
    uint256 public totalStaked;
    uint256 public totalUnstaked;
    uint256 public totalUnstaking;
    uint256 public totalWithdrawn;
    uint256 public totalFunded;
    uint256 public totalFundsRemoved;
    uint256 public totalAirdropped;
    uint256 public totalClaimed;
    uint256 public totalVested;

    uint256 public rewardsPot;
    uint256 public stakingRewardsFund;

    uint256 public penaltyPotDistributed;
    uint256 public penaltyPotElegibleSupply;
    uint256 public numberOfPotDistributions;

    uint256 public checkpointsCrossed;
    uint256 public numberOfRelocks;

    uint256 public withdrawAttempts;
    uint256 public withdrawAttemptsNoUnstaking;
    uint256 public withdrawAttemptsNotReleased;

    uint256 public time = block.timestamp;

    function reduceActors(function(address) external view returns (uint256) func) public view returns (uint256) {
        return actors.reduce(func);
    }

    function forAllActors(function(address) external returns (bool) func) external returns (bool) {
        return actors.forEach(func);
    }

    function countActors() public view returns (uint256) {
        return actors.count();
    }

    function isActor(address who) public view returns (bool) {
        return actors.contains(who);
    }

    modifier moveTime() {
        time += 1 days;
        console.log("time:", time);
        vm.warp(time);
        _;
    }

    constructor(VinciMockToken _token, VinciStakingV1 _stakingContract) {
        vinciToken = _token;
        vinciStaking = _stakingContract;
    }

    function stake(uint256 amount, address user) public moveTime {
        if ((amount % 25 == 1) && (user != address(0))) {
            actors.add(user);
            actor = user;
        } else {
            actor = actors.rand(amount);
        }

        uint256 maxAmount = 100_000_000_000 ether / 0.00025;
        amount = bound(amount, 1, maxAmount);

        vinciToken.mint(actor, amount);
        vm.prank(actor);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        _crossCheckpointIfPossible(actor);

        vm.prank(actor);
        vinciStaking.stake(amount);

        totalMinted += amount;
        totalStaked += amount;

        if (vinciStaking.isSuperstaker(actor)) {
            penaltyPotElegibleSupply += amount;
        }
    }

    function unstake(uint256 amount, uint256 actorSeed) public moveTime {
        actor = actors.rand(actorSeed);
        uint256 activeStake = vinciStaking.activeStaking(actor);
        if (activeStake == 0) return;

        uint256 maxUnstake = activeStake / 100;
        amount = bound(amount, 1, maxUnstake > 1 ? maxUnstake : 1);

        _crossCheckpointIfPossible(actor);

        if (vinciStaking.isSuperstaker(actor)) {
            penaltyPotElegibleSupply -= amount;
        }

        vm.prank(actor);
        vinciStaking.unstake(amount);

        totalUnstaking += amount;
        totalUnstaked += amount;
    }

    function claim(uint256 actorSeed) public moveTime {
        actor = actors.rand(actorSeed);
        uint256 claimable = vinciStaking.claimableBalance(actor);
        if (claimable == 0) return;

        uint256 balanceBefore = vinciToken.balanceOf(actor);

        vm.prank(actor);
        vinciStaking.claim();

        assertEq(vinciToken.balanceOf(actor), balanceBefore + claimable);
        totalClaimed += claimable;
        rewardsPot -= claimable;
    }

    function withdraw(uint256 actorSeed) public moveTime {
        actor = actors.rand(actorSeed);

        uint256 amount = vinciStaking.currentlyUnstakingBalance(actor);
        withdrawAttempts += 1;

        if (amount == 0) return;
        if (vinciStaking.unstakingReleaseTime(actor) > block.timestamp) return;

        vm.prank(actor);
        vinciStaking.withdraw();
        totalWithdrawn += amount;
        totalUnstaking -= amount;
    }

    function relock(uint256 actorSeed) public moveTime {
        // we don't want constant relocks, because otherwise we would not cross checkpoints
        if (actorSeed % 100 != 1) return;

        actor = actors.rand(actorSeed);
        if (vinciStaking.activeStaking(actor) == 0) return;

        _crossCheckpointIfPossible(actor);

        vm.prank(actor);
        vinciStaking.relock();

        numberOfRelocks += 1;
    }

    function crossCheckpoint(uint256 actorSeed) public moveTime {
        actor = actors.rand(actorSeed);
        _crossCheckpointIfPossible(actor);
    }

    function fundContract(uint256 amount) public moveTime {
        // let the contract be out of funds sometimes by funding less often
        if ((amount > 10_000_000) && (amount % 10 == 0)) return;

        amount = bound(amount, 1, 1000_000_000_000 ether / 0.00025);
        vm.startPrank(funder);
        vinciToken.mint(funder, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.fundContractWithVinciForRewards(amount);
        vm.stopPrank();

        totalMinted += amount;
        totalFunded += amount;
        rewardsPot += amount;
    }

    function removeRewardsFund(uint256 amount) public moveTime {
        // we want very seldom removals
        if (amount % 100 == 0) return;

        uint256 rewardsFunds = vinciStaking.vinciStakingRewardsFunds();
        amount = bound(amount, 0, rewardsFunds);

        vm.prank(funder);
        vinciStaking.removeNonAllocatedStakingRewards(amount);

        totalFundsRemoved += amount;
        rewardsPot -= amount;
    }

    function airdrop(uint256 amount) public moveTime {
        address to = actors.rand(amount);

        address[] memory users = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        users[0] = to;
        amounts[0] = amount;

        vm.startPrank(operator);
        vinciToken.mint(operator, amount);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.batchAirdrop(users, amounts);
        vm.stopPrank();

        totalMinted += amount;
        totalAirdropped += amount;
        rewardsPot += amount;
    }

    function distributePenaltyPot() public moveTime {
        uint256 penaltyPot = vinciStaking.penaltyPot();
        if (penaltyPot == 0) return;

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();

        penaltyPotDistributed += penaltyPot;
        numberOfPotDistributions += 1;
    }

    function _crossCheckpointIfPossible(address to) internal {
        if (!vinciStaking.canCrossCheckpoint(to)) return;

        bool superstakerBefore = vinciStaking.isSuperstaker(to);
        uint256 claimableBefore = vinciStaking.claimableBalance(to);

        vm.prank(to);
        vinciStaking.crossCheckpoint();

        if ((!superstakerBefore) && vinciStaking.isSuperstaker(to)) {
            penaltyPotElegibleSupply += vinciStaking.activeStaking(to);
        }

        checkpointsCrossed += 1;
        uint256 convertedRewards = vinciStaking.claimableBalance(to) - claimableBefore;
        totalVested += convertedRewards;
    }
}
