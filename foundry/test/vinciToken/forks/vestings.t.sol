// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

/// INVARIANT TESTS

import "@forge/src/Test.sol";
import "contracts/vinciStaking.sol";
import "contracts/vinciToken.sol";

contract ForkingTests is Test {
    Vinci vinciToken;
    VinciStakingV1 vinciStaking;

    uint256 sepoliaFork;
    address nichlaes = 0x9cd0940CCdda9BEE21869ADBA96966D8e4270a0A;
    address friend = 0xCdcf16FE529606F8656669621448EbeeE3e4Eb5a;

    function setUp() public {
        sepoliaFork = vm.createFork("https://rpc.sepolia.org");
        vinciToken = Vinci(0x243B56EDb7BD8B0Aa6fE554A4860405717b8CC4a);

        vm.selectFork(sepoliaFork);
    }

    function testForkedVestings() public view {
        uint256 ntimelocks = vinciToken.getNumberOfTimelocks(friend);
        console.log(ntimelocks);

        Vinci.TimeLock memory timelock = vinciToken.readTimelock(friend, 0);
        console.log(timelock.amount);
        console.log(timelock.releaseTime);
        console.log(timelock.claimed);
    }
}
