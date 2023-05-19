// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@forge/src/Test.sol";
import "@forge/src/StdInvariant.sol";

import "../../../../contracts/LPstaking.sol";
import "../../../../contracts/mocks/vinciLPToken.sol";
import "../../../../contracts/mocks/vinciToken.sol";
import "./lp.handler.sol";

contract LPStakingInvariants is Test {
    VinciMockToken vincitoken;
    VinciMockLPToken lptoken;
    VinciLPStaking lpstaking;
    HandlerLPstaking handler;

    address funder = makeAddr("funder");

    function setUp() public {
        vincitoken = new VinciMockToken();
        lptoken = new VinciMockLPToken();
        lpstaking = new VinciLPStaking(vincitoken,lptoken);
        handler = new HandlerLPstaking(vincitoken, lptoken, lpstaking);

        // mint a ton of vinci tokens to fund the LPstaking contract
        vm.startPrank(funder);
        uint256 fundAmount = 10_000_000_000 ether;
        vincitoken.mint(funder, fundAmount);
        vincitoken.approve(address(lpstaking), fundAmount);
        lpstaking.addVinciForInstantPayouts(fundAmount);
        handler.addToTotalVinciMinted(fundAmount);
        vm.stopPrank();

        vm.warp(lpstaking.rewardsReferenceStartingTime() + 10 weeks);

        // only this contract will be bombarded with actions
        targetContract(address(handler));

        //         select only specific functions to be bombarded
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = HandlerLPstaking.stake.selector;
        selectors[1] = HandlerLPstaking.withdraw.selector;
        selectors[2] = HandlerLPstaking.distributeAPR.selector;
        selectors[3] = HandlerLPstaking.claimRewards.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_aalogStats() public view {
        console.log("totalStaked        ", handler.totalStaked());
        console.log("totalWithdrawn     ", handler.totalWithdrawn());
        console.log("totalClaimed       ", handler.totalClaimed());
        console.log("time               ", handler.time());
        assert(true);
    }

    function invariant_LPsupply() public {
        assertEq(lptoken.totalSupply(), handler.totalLPMinted(), "total LP minted doesn't match");
    }

    function invariant_LPstakedSupply() public {
        assertEq(
            lpstaking.totalStakedLPTokens(), handler.totalStaked() - handler.totalWithdrawn(), "wrong staked supply"
        );
    }

    function invariant_VinciInTheSystem() public {
        assertEq(
            vincitoken.balanceOf(address(lpstaking)),
            handler.totalVinciMinted() - handler.totalClaimed() - handler.instantPayouts(),
            "wrong vinci in the system"
        );
    }

    function invariant_LPTokensSolvency() public {
        assertGe(lptoken.balanceOf(address(lpstaking)), handler.totalStaked() - handler.totalWithdrawn());
    }

    function invariant_RemainingVinciSolvency() public {
        assertGe(
            vincitoken.balanceOf(address(lpstaking)),
            lpstaking.fundsForStakingRewards(),
            "remainingVinci < vinci balance"
        );
    }

    function invariant_VinciTokenSolvency() public {
        assertGe(
            vincitoken.balanceOf(address(lpstaking)),
            handler.reduceActors(lpstaking.readTotalCurrentClaimable),
            "vinciBalance < totalClaimables combined"
        );
    }
}
