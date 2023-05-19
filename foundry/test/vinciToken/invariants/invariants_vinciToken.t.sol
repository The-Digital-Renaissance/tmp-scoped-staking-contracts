// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "@forge/src/StdInvariant.sol";

import "contracts/vinciToken.sol";
import "./token.handler.sol";

contract TokenInvariants is Test {
    Vinci vincitoken;
    HandlerVinciToken handler;

    address deployer = 0xfec412C75eA59Fe689C32524362EC116e7996FC0;

    function setUp() public {
        vm.prank(deployer);
        vincitoken = new Vinci();
        handler = new HandlerVinciToken(vincitoken);

        // only this contract will be bombarded with actions
        targetContract(address(handler));

        //         select only specific functions to be bombarded
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = HandlerVinciToken.setVestings.selector;
        selectors[1] = HandlerVinciToken.withdraw.selector;
        selectors[2] = HandlerVinciToken.claim.selector;
        selectors[3] = HandlerVinciToken.burn.selector;
        selectors[4] = HandlerVinciToken.skipTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_logStats() public view {
        console.log("number of actors", handler.countActors());
        console.log("free supply", handler.freeSupply());
    }

    function invariant_totalSupply() public {
        assertEq(vincitoken.totalSupply(), handler.totalSupply());
    }

    function invariant_freeSupply() public {
        assertEq(vincitoken.freeSupply(), handler.freeSupply());
    }

    function invariant_contractBalance() public {
        //The contract balance must match the sum of the freeSupply, and the unclaimed tokens from all vesting schedules
        assertEq(
            vincitoken.balanceOf(address(vincitoken)),
            handler.freeSupply() + handler.reduceActors(handler.unclaimedTokens)
        );
    }
}
