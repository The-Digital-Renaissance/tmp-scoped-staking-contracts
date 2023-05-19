// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "../../../contracts/vinciToken.sol";

contract BaseVinciToken is Test {
    Vinci vinci;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    function setUp() public virtual {
        vinci = new Vinci();
    }
}
