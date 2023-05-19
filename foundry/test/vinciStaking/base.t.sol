// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
//import "../../../contracts/tiers.sol";
import "../../../contracts/vinciStaking.sol";
import "../../../contracts/mocks/vinciToken.sol";

contract BaseTestNotFunded is Test {
    VinciMockToken vinciToken;
    VinciStakingV1 vinciStaking;

    address funder = makeAddr("funder");
    address operator = makeAddr("contractOperator");

    address user = makeAddr("user");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address pepe = makeAddr("pepe");

    address nonUser = makeAddr("nonUser");

    function setUp() public virtual {
        // virtual is to allow overrides of other test contracts

        vinciToken = new VinciMockToken();

        // [800000000000000000000000,8000000000000000000000000,40000000000000000000000000,200000000000000000000000000,1000000000000000000000000000]
        uint128 tier1 = 200 * 1e18 / 0.00025;
        uint128 tier2 = 2000 * 1e18 / 0.00025;
        uint128 tier3 = 10000 * 1e18 / 0.00025;
        uint128 tier4 = 50000 * 1e18 / 0.00025;
        uint128 tier5 = 250000 * 1e18 / 0.00025;

        uint128[] memory tiers = new uint128[](6);
        // 200$ * 0.00025 ($/V) * 1e18 (decimals/V)
        tiers[0] = tier1;
        tiers[1] = tier2;
        tiers[2] = tier3;
        tiers[3] = tier4;
        tiers[4] = tier5;

        vinciStaking = new VinciStakingV1(vinciToken, tiers);

        // lets make the vinci funder very rich first
        vinciToken.mint(funder, 1_000_000_000 ether);
        vinciToken.mint(user, 100_000_000 ether);
        vinciToken.mint(alice, 100_000_000 ether);
        vinciToken.mint(pepe, 100_000_000 ether);
        vinciToken.mint(bob, 100_000_000 ether);

        vm.prank(funder);
        vinciToken.approve(address(vinciStaking), type(uint256).max);

        // lets give this role to the funder so that he can stake in behalf of users
        vinciStaking.grantRole(vinciStaking.CONTRACT_OPERATOR_ROLE(), funder);
        vinciStaking.grantRole(vinciStaking.CONTRACT_OPERATOR_ROLE(), operator);

        vinciStaking.grantRole(vinciStaking.CONTRACT_FUNDER_ROLE(), funder);

        vm.prank(operator);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
    }

    function _estimateRewards(uint256 stakeAmount, uint256 durationSecs) internal view returns (uint256) {
        return stakeAmount * vinciStaking.BASE_APR() * durationSecs / (365 days * vinciStaking.BASIS_POINTS());
    }

    function _createUsers() internal view returns (address[] memory) {
        address[] memory users = new address[](4);
        users[0] = user;
        users[1] = alice;
        users[2] = bob;
        users[3] = pepe;
        return users;
    }

    // handy function to test batch staking
    function _createAmounts() internal pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;
        amounts[3] = 400 ether;
        return amounts;
    }
}

contract BaseTestFunded is BaseTestNotFunded {
    function setUp() public virtual override {
        // virtual is to allow overrides of other test contracts
        // override is to override the setup() of BaseTestNotFunded
        super.setUp();

        vinciToken.mint(funder, 1_000_000_000_000 ether);

        vm.prank(funder);
        vinciStaking.fundContractWithVinciForRewards(1_000_000_000 ether);

        vm.prank(operator);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
    }

    function _airdrop(address user, uint256 amount) internal {
        address[] memory users = new address[](1);
        users[0] = user;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(funder);
        vinciStaking.batchAirdrop(users, amounts);
    }

    function _estimatePenalty(address who, uint256 unstakeAmount) internal view returns (uint256) {
        uint256 stakeAmount = vinciStaking.activeStaking(who);
        uint256 unclaimable = vinciStaking.getTotalUnclaimableBalance(who);
        return unclaimable * unstakeAmount / stakeAmount;
    }

    function _fillPotWithoutDistribution() internal {
        vm.startPrank(alice);
        vinciToken.mint(alice, 8_000_000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(8_000_000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        vinciToken.mint(bob, 10_000_000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(10_000_000 ether);
        vm.stopPrank();

        vm.startPrank(pepe);
        vinciToken.mint(pepe, 10_000_000 ether);
        vinciToken.approve(address(vinciStaking), type(uint256).max);
        vinciStaking.stake(10_000_000 ether);
        vm.stopPrank();

        skip(57 days);
        vm.prank(bob);
        vinciStaking.unstake(7_500_000 ether);

        skip(10 days);
        vm.prank(pepe);
        vinciStaking.unstake(5_100_000 ether);

        skip(7 days);
        vm.prank(alice);
        vinciStaking.unstake(100_000 ether);
    }

    function _fillAndDistributePenaltyPotOrganically() internal {
        _fillPotWithoutDistribution();

        vm.prank(operator);
        vinciStaking.distributePenaltyPot();
    }
}
