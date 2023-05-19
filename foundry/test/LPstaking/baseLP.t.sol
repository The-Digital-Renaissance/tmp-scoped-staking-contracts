// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/LPstaking.sol";
import "../../../contracts/mocks/vinciToken.sol";
import "../../../contracts/mocks/vinciLPToken.sol";

contract BaseLPTestNotFunded is Test {
    VinciLPStaking stakingcontract;
    VinciMockToken vinciToken;
    VinciMockLPToken lptoken;

    address holder1 = makeAddr("holder1");
    address holder2 = makeAddr("holder2");
    address holder3 = makeAddr("holder3");
    address funder = makeAddr("funder");

    function setUp() public {
        // bring time to expected deployment time: 31 May 2023 02:00:00 GMT+02:00
        vm.warp(1685491200);

        vinciToken = new VinciMockToken();
        lptoken = new VinciMockLPToken();
        stakingcontract = new VinciLPStaking(vinciToken, lptoken);

        vm.startPrank(holder1);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(holder2);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(holder3);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(funder);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();

        // this value is completely made up and it is unkown until the liquidity pool is created
        stakingcontract.setLPPriceInVinci(0.0025 ether);
    }
}

contract BaseLPTestFunded is Test {
    VinciLPStaking stakingcontract;
    VinciMockToken vinciToken;
    VinciMockLPToken lptoken;

    address holder1 = makeAddr("holder1");
    address holder2 = makeAddr("holder2");
    address holder3 = makeAddr("holder3");
    address funder = makeAddr("funder");

    function setUp() public {
        // bring time to expected deployment time: 31 May 2023 02:00:00 GMT+02:00
        vm.warp(1685491200);

        vinciToken = new VinciMockToken();
        lptoken = new VinciMockLPToken();
        stakingcontract = new VinciLPStaking(vinciToken, lptoken);

        vm.startPrank(holder1);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(holder2);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(holder3);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(funder);
        vinciToken.approve(address(stakingcontract), type(uint256).max);
        lptoken.approve(address(stakingcontract), type(uint256).max);
        vm.stopPrank();

        // this value is completely made up and it is unkown until the liquidity pool is created
        stakingcontract.setLPPriceInVinci(0.0025 ether);

        vm.startPrank(funder);
        vinciToken.mint(funder, 100000000000000 ether);
        stakingcontract.addVinciForInstantPayouts(100000000000000 ether);
        vinciToken.mint(funder, 100000000000000 ether);
        stakingcontract.addVinciForStakingRewards(100000000000000 ether);
        vm.stopPrank();
    }
}
