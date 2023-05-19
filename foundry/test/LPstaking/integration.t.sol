// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./baseLP.t.sol";

contract IntegrationTests is BaseLPTestFunded {
    function testStakeDistributeStake() public {
        skip(8 days);

        // stake lp tokens
        lptoken.mint(holder1, 3939);
        vm.prank(holder1);
        stakingcontract.newStake(3939, 4);

        // distribute some APR
        stakingcontract.distributeWeeklyAPR();

        // stake again
        uint256 amount2 = 92213209040297279295005628866569;
        lptoken.mint(holder2, amount2);
        vm.prank(holder2);
        stakingcontract.newStake(amount2, 4);

        // assert for solvency
        uint256 claimable1 = stakingcontract.readTotalCurrentClaimable(holder1);
        uint256 claimable2 = stakingcontract.readTotalCurrentClaimable(holder2);
        assertGe(
            vinciToken.balanceOf(address(stakingcontract)),
            claimable1 + claimable2,
            "vinciBalance < total Claimables combined"
        );
    }
}
