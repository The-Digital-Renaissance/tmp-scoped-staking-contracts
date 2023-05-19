// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/inheritables/tiers.sol";
import "./base.t.sol";

/// CONTRACT FUNDING TESTS ///
// events
// calculating tiers based on thresholds
// view number of tiers
// successful change of tiers
// read tiers

contract TestTiers is BaseTestFunded {
    event TiersThresholdsUpdated(uint128[] vinciThresholds);

    function testNumberOftiers() public {
        uint128[] memory tiers = new uint128[](4);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;
        tiers[3] = 10000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getNumberOfTiers(), 4);
    }

    function testUpdateThresholdsEvent() public {
        uint128[] memory tiers = new uint128[](4);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;
        tiers[3] = 10000 ether;

        vm.expectEmit(false, false, false, true);
        emit TiersThresholdsUpdated(tiers);
        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);
    }

    function testReadTiers() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getTierThreshold(0), 0);
        assertEq(vinciStaking.getTierThreshold(1), 10 ether);
        assertEq(vinciStaking.getTierThreshold(2), 100 ether);
        assertEq(vinciStaking.getTierThreshold(3), 1000 ether);
    }

    function testReadAndWrittenTiers() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10;
        tiers[1] = 100;
        tiers[2] = 1000;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getTierThreshold(0), 0);
        assertEq(vinciStaking.getTierThreshold(1), 10);
        assertEq(vinciStaking.getTierThreshold(2), 100);
        assertEq(vinciStaking.getTierThreshold(3), 1000);
        vm.expectRevert();
        vinciStaking.getTierThreshold(4);

        assertEq(vinciStaking.calculateTier(0), 0);
        assertEq(vinciStaking.calculateTier(9), 0);
        assertEq(vinciStaking.calculateTier(10), 1);
        assertEq(vinciStaking.calculateTier(11), 1);
        assertEq(vinciStaking.calculateTier(99), 1);
        assertEq(vinciStaking.calculateTier(100), 2);
        assertEq(vinciStaking.calculateTier(101), 2);
        assertEq(vinciStaking.calculateTier(999), 2);
        assertEq(vinciStaking.calculateTier(1000), 3);
        assertEq(vinciStaking.calculateTier(30000000), 3);

        console.log("getTierThreshold(0)", vinciStaking.getTierThreshold(0));
        console.log("getTierThreshold(1)", vinciStaking.getTierThreshold(1));
        console.log("getTierThreshold(2)", vinciStaking.getTierThreshold(2));
        console.log("getTierThreshold(3)", vinciStaking.getTierThreshold(3));
        vm.expectRevert();
        console.log("getTierThreshold(4)", vinciStaking.getTierThreshold(4));

        console.log("calculateTier(0)", vinciStaking.calculateTier(0));
        console.log("calculateTier(9)", vinciStaking.calculateTier(9));
        console.log("calculateTier(10)", vinciStaking.calculateTier(10));
        console.log("calculateTier(11)", vinciStaking.calculateTier(11));
        console.log("calculateTier(99)", vinciStaking.calculateTier(99));
        console.log("calculateTier(100)", vinciStaking.calculateTier(100));
        console.log("calculateTier(101)", vinciStaking.calculateTier(101));
        console.log("calculateTier(999)", vinciStaking.calculateTier(999));
        console.log("calculateTier(1000)", vinciStaking.calculateTier(1000));
        console.log("calculateTier(30000000)", vinciStaking.calculateTier(30000000));
    }

    function testExceedMaxTiers() public {
        uint128[] memory tiers = new uint128[](11);
        tiers[0] = 10;
        tiers[1] = 100;
        tiers[2] = 1000;
        tiers[3] = 100010;
        tiers[4] = 100020;
        tiers[5] = 100030;
        tiers[6] = 100040;
        tiers[7] = 100050;
        tiers[8] = 100060;
        tiers[9] = 100070;
        tiers[10] = 1000700;

        vm.prank(operator);
        vm.expectRevert(TooManyTiers.selector);
        vinciStaking.updateTierThresholds(tiers);
    }

    function testReadAndWritten10Tiers() public {
        uint128[] memory tiers = new uint128[](10);
        tiers[0] = 10;
        tiers[1] = 100;
        tiers[2] = 1000;
        tiers[3] = 100010;
        tiers[4] = 100020;
        tiers[5] = 100030;
        tiers[6] = 100040;
        tiers[7] = 100050;
        tiers[8] = 100060;
        tiers[9] = 100070;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.calculateTier(0), 0);
        assertEq(vinciStaking.calculateTier(9), 0);
        assertEq(vinciStaking.calculateTier(100060), 9);
        assertEq(vinciStaking.calculateTier(100061), 9);
        assertEq(vinciStaking.calculateTier(100070), 10);
        assertEq(vinciStaking.calculateTier(10007099), 10);
    }

    function testTierCalculation() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getNumberOfTiers(), 3);

        assertEq(vinciStaking.calculateTier(0), 0);
        assertEq(vinciStaking.calculateTier(10 ether - 1), 0);
        assertEq(vinciStaking.calculateTier(10 ether), 1);
        assertEq(vinciStaking.calculateTier(10 ether + 1), 1);
        assertEq(vinciStaking.calculateTier(100 ether - 1), 1);
        assertEq(vinciStaking.calculateTier(100 ether), 2);
        assertEq(vinciStaking.calculateTier(100 ether + 1), 2);
        assertEq(vinciStaking.calculateTier(1000 ether - 1), 2);
        assertEq(vinciStaking.calculateTier(1000 ether), 3);
        assertEq(vinciStaking.calculateTier(1000 ether + 1), 3);
        assertEq(vinciStaking.calculateTier(10000000 ether), 3);
        assertEq(vinciStaking.calculateTier(100000000000000 ether), 3);
    }

    function testUpdateTiersByRandomWallet() public {
        uint128[] memory newTiers = new uint128[](2);
        newTiers[0] = 20 ether;
        newTiers[1] = 200 ether;

        // the default
        address malicious = makeAddr("malicious");
        vm.prank(malicious);
        vm.expectRevert();
        vinciStaking.updateTierThresholds(newTiers);

        // make sure the reason it reverts is because of the access control by repeating the same tx with different address successfully
        vm.prank(operator);
        vinciStaking.updateTierThresholds(newTiers);
    }

    function testUpdateTiers() public {
        uint128[] memory newTiers = new uint128[](2);
        newTiers[0] = 20 ether;
        newTiers[1] = 200 ether;

        // the default
        vm.prank(operator);
        vinciStaking.updateTierThresholds(newTiers);

        assertEq(vinciStaking.getNumberOfTiers(), 2);

        assertEq(vinciStaking.getTierThreshold(0), 0);
        assertEq(vinciStaking.getTierThreshold(1), 20 ether);
        assertEq(vinciStaking.getTierThreshold(2), 200 ether);
        vm.expectRevert(NonExistingTier.selector);
        vinciStaking.getTierThreshold(3);
        vm.expectRevert(NonExistingTier.selector);
        vinciStaking.getTierThreshold(4);

        assertEq(vinciStaking.calculateTier(0), 0);
        assertEq(vinciStaking.calculateTier(20 ether - 1), 0);
        assertEq(vinciStaking.calculateTier(20 ether), 1);
        assertEq(vinciStaking.calculateTier(200 ether - 1), 1);
        assertEq(vinciStaking.calculateTier(200 ether), 2);
        assertEq(vinciStaking.calculateTier(2000 ether - 1), 2);
        assertEq(vinciStaking.calculateTier(2000 ether), 2);
        assertEq(vinciStaking.calculateTier(20000000 ether), 2);
    }

    function testUpdateTiersWithShorterLength() public {
        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getNumberOfTiers(), 3);
        assertEq(vinciStaking.getTierThreshold(1), 10 ether);
        assertEq(vinciStaking.getTierThreshold(2), 100 ether);
        assertEq(vinciStaking.getTierThreshold(3), 1000 ether);

        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(4), 0);
        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(5), 0);
        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(6), 0);
    }

    function testUpdateTiersWithLongerLength() public {
        uint128[] memory tiers = new uint128[](8);
        tiers[0] = 1 ether;
        tiers[1] = 5 ether;
        tiers[2] = 10 ether;
        tiers[3] = 50 ether;
        tiers[4] = 100 ether;
        tiers[5] = 200 ether;
        tiers[6] = 500 ether;
        tiers[7] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getNumberOfTiers(), 8);
        assertEq(vinciStaking.getTierThreshold(1), 1 ether);
        assertEq(vinciStaking.getTierThreshold(2), 5 ether);
        assertEq(vinciStaking.getTierThreshold(3), 10 ether);
        assertEq(vinciStaking.getTierThreshold(4), 50 ether);
        assertEq(vinciStaking.getTierThreshold(5), 100 ether);
        assertEq(vinciStaking.getTierThreshold(6), 200 ether);
        assertEq(vinciStaking.getTierThreshold(7), 500 ether);
        assertEq(vinciStaking.getTierThreshold(8), 1000 ether);

        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(9), 0);
        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(10), 0);
        vm.expectRevert(NonExistingTier.selector);
        assertEq(vinciStaking.getTierThreshold(11), 0);
    }

    function testTierZeroThreshold() public {
        // tier0 should always have the threshold 0
        assertEq(vinciStaking.getTierThreshold(0), 0);

        uint128[] memory tiers = new uint128[](3);
        tiers[0] = 10 ether;
        tiers[1] = 100 ether;
        tiers[2] = 1000 ether;

        vm.prank(operator);
        vinciStaking.updateTierThresholds(tiers);

        assertEq(vinciStaking.getTierThreshold(0), 0);
    }
}
