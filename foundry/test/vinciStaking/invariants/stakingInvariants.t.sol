// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

/// INVARIANT TESTS

import "@forge/src/Test.sol";
import "@forge/src/StdInvariant.sol";
import "contracts/vinciStaking.sol";
import "contracts/mocks/vinciToken.sol";
import "./stakingHandler.sol";

contract StakingV1Invariants is Test {
    VinciMockToken vinciToken;
    VinciStakingV1 vinciStaking;
    StakingHandler handler;

    address funder = makeAddr("funder");
    address operator = makeAddr("operator");

    uint256 deployTime;

    function setUp() public {
        // 200$ * 0.00025 ($/V) * 1e18 (decimals/V)
        uint128 tier1 = 200 * 1e18 / 0.00025;
        uint128 tier2 = 2000 * 1e18 / 0.00025;
        uint128 tier3 = 10000 * 1e18 / 0.00025;
        uint128 tier4 = 50000 * 1e18 / 0.00025;
        uint128 tier5 = 250000 * 1e18 / 0.00025;

        uint128[] memory tiers = new uint128[](6);
        tiers[0] = tier1;
        tiers[1] = tier2;
        tiers[2] = tier3;
        tiers[3] = tier4;
        tiers[4] = tier5;

        vinciToken = new VinciMockToken();
        vinciStaking = new VinciStakingV1(vinciToken, tiers);
        handler = new StakingHandler(vinciToken, vinciStaking);

        vinciStaking.grantRole(vinciStaking.CONTRACT_OPERATOR_ROLE(), operator);
        vinciStaking.grantRole(vinciStaking.CONTRACT_FUNDER_ROLE(), funder);

        deployTime = block.timestamp;

        // lets fund the contract

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = StakingHandler.stake.selector;
        selectors[1] = StakingHandler.unstake.selector;
        selectors[2] = StakingHandler.fundContract.selector;
        selectors[3] = StakingHandler.withdraw.selector;
        selectors[4] = StakingHandler.crossCheckpoint.selector;
        selectors[5] = StakingHandler.claim.selector;
        selectors[6] = StakingHandler.distributePenaltyPot.selector;
        selectors[7] = StakingHandler.relock.selector;
        selectors[8] = StakingHandler.removeRewardsFund.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_aalogStats() public view {
        console.log("totalStaked                        ", handler.totalStaked());
        console.log("totalFunded                        ", handler.totalFunded());
        console.log("totalFundsRemoved                  ", handler.totalFundsRemoved());
        console.log("totalMinted                        ", handler.totalMinted());
        console.log("totalWithdrawn                     ", handler.totalWithdrawn());
        console.log("totalClaimed                       ", handler.totalClaimed());
        console.log("totalUnstaked                      ", handler.totalUnstaked());
        console.log("totalVested                        ", handler.totalVested());
        console.log("totalAirdropped                    ", handler.totalAirdropped());
        console.log("penaltyPotDistributed              ", handler.penaltyPotDistributed());
        console.log("penaltyPotElegibleSupply           ", handler.penaltyPotElegibleSupply());
        console.log("numberOfPotDistributions           ", handler.numberOfPotDistributions());
        console.log("checkpoints crossed                ", handler.checkpointsCrossed());
        console.log("number of relocks                  ", handler.numberOfRelocks());
        console.log("total days passed                  ", handler.time() / (1 days));
        console.log("number of actors                   ", handler.countActors());
        assert(true);
    }

    function invariant_cashflow() public {
        // [token inflows] - [token outflows] = [contract balance]
        uint256 inflows = handler.totalStaked() + handler.totalAirdropped() + handler.totalFunded();
        uint256 outflows = handler.totalWithdrawn() + handler.totalClaimed() + handler.totalFundsRemoved();
        assertEq(inflows - outflows, vinciToken.balanceOf(address(vinciStaking)));
    }

    function invariant_stakingCashflow() public {
        // [staked in] - [withdrawals] = total staked tokens = (total stakign balance - currently unstaking)
        uint256 stakedIn = handler.totalStaked();
        uint256 withdrawals = handler.totalWithdrawn();
        assertEq(
            stakedIn - withdrawals,
            vinciStaking.totalVinciStaked() + handler.reduceActors(vinciStaking.currentlyUnstakingBalance)
        );
    }

    function invariant_totalStaked() public {
        assertEq(handler.totalStaked() - handler.totalUnstaked(), vinciStaking.totalVinciStaked());
    }

    function invariant_currentlyUnstaking() public {
        assertEq(
            handler.totalUnstaked() - handler.totalWithdrawn(),
            handler.reduceActors(vinciStaking.currentlyUnstakingBalance)
        );
    }

    function invariant_activeStaking() public {
        assertEq(vinciStaking.totalVinciStaked(), handler.reduceActors(vinciStaking.activeStaking));
    }

    function invariant_penaltyPotElegibleSupply() public {
        assertApproxEqAbs(
            vinciStaking.getSupplyEligibleForPenaltyPot(),
            handler.penaltyPotElegibleSupply(),
            vinciStaking.PENALTYPOT_ROUNDING_FACTOR()
        );
    }

    function invariant_reducedCheckPrincipals() public {
        assertEq(
            handler.totalStaked() - handler.totalWithdrawn(),
            handler.reduceActors(vinciStaking.activeStaking)
                + handler.reduceActors(vinciStaking.currentlyUnstakingBalance)
        );
    }

    function invariant_sumOfClaimables() public {
        assertEq(handler.totalVested() - handler.totalClaimed(), handler.reduceActors(vinciStaking.claimableBalance));
    }

    function invariant_principalsAndVestedSolvency() public {
        // the contract should be able to face at any time the withdrawal of all pricnipals, all vested rewards
        uint256 principals = handler.totalStaked() - handler.totalWithdrawn();
        uint256 unclaimedVestedRewards = handler.totalVested() - handler.totalClaimed();
        assertGe(vinciToken.balanceOf(address(vinciStaking)), principals + unclaimedVestedRewards);
    }

    function invariant_stakesAndClaimsSolvencyReduce() public {
        // the contract should be able to face at any time the withdrawal of all pricnipals, all vested rewards
        uint256 principals = handler.totalStaked() - handler.totalWithdrawn();
        uint256 unclaimedVestedRewards = handler.reduceActors(vinciStaking.claimableBalance);
        assertGe(vinciToken.balanceOf(address(vinciStaking)), principals + unclaimedVestedRewards);
    }

    function invariant_unvestedRewardsSolvency() public {
        // [rewards inflow] - [rewards outflow] = [contract balance for rewards]
        uint256 unvestedRewardsInflow = handler.totalFunded() + handler.totalAirdropped();
        uint256 unvestedRewardsOutflow = handler.totalFundsRemoved() + handler.totalVested();
        uint256 unvestedRewardsBalance = handler.reduceActors(vinciStaking.fullPeriodAprRewards);
        // the unclaimable does not include yet all rewards, only the ones that have been unlocked so far
        assertGe(unvestedRewardsInflow - unvestedRewardsOutflow, unvestedRewardsBalance);
    }

    //    function invariant_stakingRewardsFunds() public {
    //        // [inflow rewards funds] - [outflow rewards funds] = [rewards funds balance]
    //        // inflow = funded, returned funds after unstaking
    //        // outflow = funds removed, funds allocated to APR rewards
    // TODO: here we miss to include the funds that are allocated to fulPeriodApr
    //        assertEq(handler.totalFunded() - handler.totalFundsRemoved(), vinciStaking.vinciStakingRewardsFunds());
    //    }

    // TODO:

    function invariant_rewardsPool() public {
        // The following set of balances act as a pool:
        // rewards funds, penalty pot, reserved staking rewards (fullPeriodAprRewards), the unvested airdrops and the claimable balance

        uint256 rewardsPot = vinciStaking.vinciStakingRewardsFunds() + vinciStaking.penaltyPot()
            + handler.reduceActors(vinciStaking.fullPeriodAprRewards)
            + handler.reduceActors(vinciStaking.getUnclaimableFromAirdrops)
            + handler.reduceActors(vinciStaking.claimableBalance);
        assertGe(rewardsPot + vinciStaking.PENALTYPOT_ROUNDING_FACTOR(), handler.rewardsPot());
    }

    function invariant_unvestedRewardsClosedSystemConservation() public {
        // [unvested rewards inflow] - [unvested rewards outflow] = [unvested rewards balance]
        uint256 unvestedRewardsInflow = handler.totalFunded() + handler.totalAirdropped();
        uint256 unvestedRewardsOutflow = handler.totalFundsRemoved() + handler.totalVested();

        // all allocated rewards are unvested + all airdrops + unallocated penalty pot + allocated penalty pot
        uint256 unvestedRewardsBalance = vinciStaking.vinciStakingRewardsFunds()
            + handler.reduceActors(vinciStaking.fullPeriodAprRewards)
            + handler.reduceActors(vinciStaking.getUnclaimableFromAirdrops)
            + handler.reduceActors(vinciStaking.getUnclaimableFromPenaltyPot) + vinciStaking.penaltyPot();
        // the unclaimable does not include yet all rewards, only the ones that have been unlocked so far
        assertGe(
            unvestedRewardsInflow - unvestedRewardsOutflow + vinciStaking.PENALTYPOT_ROUNDING_FACTOR(),
            unvestedRewardsBalance
        );
    }

    function invariant_unvestedRewardsCashflow() public {
        // [rewards inflow] - [rewards outflow] = [contract balance for rewards]
        uint256 unvestedRewardsInflow = handler.totalFunded() + handler.totalAirdropped();
        uint256 unvestedRewardsOutflow = handler.totalFundsRemoved() + handler.totalVested();
        // the unvested rewards in the contract are distributed between: stakingRewardsFunds, fullPeriodAprRewards, unclaimableFromAirdrops, unclaimableFromPenaltyPot, penaltyPot
        // APR rewards are in the stakingRewardsFund, and are moved to fullPeriodRewards when allocated
        // rewards from penalty pot are in penaltyPot until they are distributed to the individual allocations
        uint256 unvestedRewardsBalance = vinciStaking.vinciStakingRewardsFunds()
            + handler.reduceActors(vinciStaking.fullPeriodAprRewards)
            + handler.reduceActors(vinciStaking.getUnclaimableFromAirdrops)
            + handler.reduceActors(vinciStaking.getUnclaimableFromPenaltyPot) + vinciStaking.penaltyPot();
        // the unclaimable does not include yet all rewards
        //        assertApproxEqAbs(unvestedRewardsInflow - unvestedRewardsOutflow, unvestedRewardsBalance, vinciStaking.PENALTYPOT_ROUNDING_FACTOR());
        assertGe(
            unvestedRewardsInflow - unvestedRewardsOutflow + vinciStaking.PENALTYPOT_ROUNDING_FACTOR(),
            unvestedRewardsBalance
        );
    }
}
