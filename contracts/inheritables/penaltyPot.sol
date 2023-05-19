// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

/// This contract handles the penalty pot.
/// There are two stages of the balance
/// Vinci tokens are first deposited into the penaltyPool
/// Regularly, the contract owner will 'distribute' the penaltyPool between users, allocating the amounts proportional
/// to their share of the supplyElegibleForPenaltyPot
/// However, none of the two above are 'claimable' until a checkpoint is crossed and they go to the claimable balance

contract PenaltyPot {
    // Supply is tracked with limited number of decimals. This is done to avoid loosing decimals in _distributePenaltyPot()
    uint256 public constant PENALTYPOT_SUPPLY_DECIMALS = 3;
    uint256 public constant PENALTYPOT_ROUNDING_FACTOR = 10 ** (18 - PENALTYPOT_SUPPLY_DECIMALS);
    uint256 internal supplyElegibleForAllocation;
    // The amount of vinci tokens that are allocated to each staked vinci token belonging to elegible supply
    uint256 internal allocationPerStakedVinci;

    // The actual pool tracking all deposited tokens from penalized stakers
    uint256 internal penaltyPool;
    // In every distribution, some decimals would be lost, so they are buffered here
    uint256 internal bufferedVinci;

    // These variables are used to track the decimals lost in supplyElegibleForAllocation in additions and removals
    uint256 internal bufferedDecimalsInSupplyAdditions;
    uint256 internal bufferedDecimalsInSupplyRemovals;

    mapping(address => uint256) internal individualAllocationTracker;
    mapping(address => uint256) internal individualBuffer;

    event DepositedToPenaltyPot(address user, uint256 amountDeposited);
    event PenaltyPotDistributed(uint256 amountDistributed, uint256 bufferedDecimals);

    function _depositToPenaltyPot(uint256 amount) internal {
        penaltyPool += amount;
        emit DepositedToPenaltyPot(msg.sender, amount);
    }

    /// @dev    Here the pool is distributed into individual allocations (not claimable yet)
    function _distributePenaltyPot() internal {
        uint256 elegibleSupply = supplyElegibleForAllocation;

        if (elegibleSupply == 0) {
            bufferedVinci += penaltyPool;
            penaltyPool = 0;
            emit PenaltyPotDistributed(0, bufferedVinci);
            return;
        }

        uint256 totalToDistribute = penaltyPool + bufferedVinci;

        // elegible supply is divided by the PENALTYPOT_ROUNDING_FACTOR, so distributePerVinci (and therefore allocationPerStakedVinci)
        // are artificially boosted
        uint256 distributePerVinci = totalToDistribute / elegibleSupply;
        uint256 lostDecimals = totalToDistribute % elegibleSupply;
        // overwriting bufferedDecimals is intentional, as the old decimals are included in `totalToDistribute`
        bufferedVinci = lostDecimals;
        allocationPerStakedVinci += distributePerVinci;
        penaltyPool = 0;

        emit PenaltyPotDistributed(distributePerVinci * elegibleSupply, lostDecimals);
    }

    function _bufferPenaltyPotAllocation(address user, uint256 _stakingBalance) internal returns (uint256) {
        // the individualBuffer is already converted to the right amount of decimals
        uint256 allocation = _stakingBalance * (allocationPerStakedVinci - individualAllocationTracker[user])
            / PENALTYPOT_ROUNDING_FACTOR;
        individualAllocationTracker[user] = allocationPerStakedVinci;
        // here we store the newBuffer in memory to save gas, to avoid read and writes of individualBuffer from storage
        uint256 newBuffer = individualBuffer[user] + allocation;
        individualBuffer[user] = newBuffer;
        return newBuffer;
    }

    function _addToElegibleSupplyForPenaltyPot(uint256 amount) internal {
        uint256 amountToAdd = amount + bufferedDecimalsInSupplyAdditions;
        supplyElegibleForAllocation += (amountToAdd / PENALTYPOT_ROUNDING_FACTOR);
        // overwriting is intentional, as the old decimals are included in `amountToAdd`
        bufferedDecimalsInSupplyAdditions = amountToAdd % PENALTYPOT_ROUNDING_FACTOR;
    }

    function _removeFromElegibleSupplyForPenaltyPot(uint256 amount) internal {
        uint256 amountToRemove = amount + bufferedDecimalsInSupplyRemovals;
        supplyElegibleForAllocation -= (amountToRemove / PENALTYPOT_ROUNDING_FACTOR);
        // overwriting is intentional, as the old decimals are included in `amountToRemove`
        bufferedDecimalsInSupplyRemovals = amountToRemove % PENALTYPOT_ROUNDING_FACTOR;
    }

    // @dev The penalization only needs to be done on the amount that has been already distributed. The non distribtued
    //      one is penalized automatically because of decreasing the share by unstaking
    function _penalizePenaltyPotShare(address user, uint256 unstakeAmount, uint256 stakingBalanceBefPenalization)
        internal
        returns (uint256)
    {
        // once buffered, there is no other allocation for user besides the `individualBuffer`
        uint256 updatedBuffer = _bufferPenaltyPotAllocation(user, stakingBalanceBefPenalization);
        uint256 penalization = updatedBuffer * unstakeAmount / stakingBalanceBefPenalization;
        updatedBuffer -= penalization;
        individualBuffer[user] = updatedBuffer;
        return penalization;
    }

    // @dev This only redeems the amount that has been already distributed
    function _redeemPenaltyPot(address user, uint256 _stakingBalance) internal returns (uint256) {
        uint256 updatedBuffer = _bufferPenaltyPotAllocation(user, _stakingBalance);
        delete individualBuffer[user];
        return updatedBuffer;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////
    // @dev This one only shows the allocated penalty pot. The one that is actually asigned to a user
    //      The allocated is the one showing as unclaimable balance in VinciStaking
    function _getAllocatedSharePenaltyPot(address user, uint256 _stakingBalance) internal view returns (uint256) {
        return individualBuffer[user]
            + _stakingBalance * (allocationPerStakedVinci - individualAllocationTracker[user]) / PENALTYPOT_ROUNDING_FACTOR;
    }

    // @dev This estimation takes into account both the distributed and the non-distributed amounts
    //      Note however that the distributed is not claimable yet either. This value however is not final until
    //      distributed.
    function _estimateUserShareOfPenaltyPot(address user, uint256 _stakingBalance) internal view returns (uint256) {
        if (supplyElegibleForAllocation == 0) return 0;

        return _getAllocatedSharePenaltyPot(user, _stakingBalance)
            + (_stakingBalance * penaltyPool) / (supplyElegibleForAllocation * PENALTYPOT_ROUNDING_FACTOR);
    }

    // @dev This is the penalty pot that has not been distributed yet
    function _getTotalPenaltyPot() internal view returns (uint256) {
        return penaltyPool + bufferedVinci;
    }

    function _getSupplyElegibleForAllocation() internal view returns (uint256) {
        return (supplyElegibleForAllocation * PENALTYPOT_ROUNDING_FACTOR) + bufferedDecimalsInSupplyAdditions
            - bufferedDecimalsInSupplyRemovals;
    }
}
