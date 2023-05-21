// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

contract Checkpoints {
    /// user timestamp when next checkpoint can be crossed
    mapping(address => uint256) internal checkpoint;
    /// checkpoints are postponed in multiples of 30 days. The checkpointReduction is how many blocks of 30 days the current checkpoint has been reduced from the BASE_CHECKPOINT_MULTIPLIER.
    mapping(address => uint256) internal checkpointMultiplierReduction; // Initialized at 0, increasing up to 5

    /// the checkpoint multiplier is reduced by 1 block every time a user crosses a checkpoint. The starting multiplier is this
    uint256 internal constant BASE_CHECKPOINT_MULTIPLIER = 6;
    uint256 internal constant BASE_CHECKPOINT_DURATION = 30 days;

    event CheckpointSet(address indexed user, uint256 newCheckpoint);

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Internal functions (inheritable by VinciStaking)

    function _checkpointMultiplier(address user) internal view returns (uint256) {
        return BASE_CHECKPOINT_MULTIPLIER - checkpointMultiplierReduction[user];
    }

    /// @dev    This function will update as many checkpoints as crossed
    ///         It will return the length of the missed period, the start of this checkpoint-period and the next checkpoint
    function _postponeCheckpoint(address user) internal returns (uint256, uint256, uint256) {
        bool reductorNeedsUpdate = false;
        uint256 missedPeriod;
        uint256 checkpointPeriodStart;
        uint256 nextCheckpoint = checkpoint[user];

        // store these in memory for gas savings
        uint256 _reduction = checkpointMultiplierReduction[user];
        while (nextCheckpoint < block.timestamp) {
            // the checkpoint multiplier cannot be less than 1, so the reduction cannot be more than (BASE_CHECKPOINT_MULTIPLIER - 1)
            if (_reduction + 1 < BASE_CHECKPOINT_MULTIPLIER) {
                _reduction += 1;
                reductorNeedsUpdate = true;
            }
            // addition to the current checkpoint to ignore the delay from the time when it is possible and the moment when crossing is actually executed
            uint256 timeAddition = (BASE_CHECKPOINT_MULTIPLIER - _reduction) * BASE_CHECKPOINT_DURATION;
            nextCheckpoint += timeAddition;
            // if a user misses multiple periods, we need to compensate the APR lost from those periods
            if (nextCheckpoint < block.timestamp) {
                missedPeriod += timeAddition;
            }
        }
        // we only need to overwrite checkpointMultiplierReduction if it has actually changed
        if (reductorNeedsUpdate) {
            checkpointMultiplierReduction[user] = _reduction;
        }
        checkpoint[user] = nextCheckpoint;
        checkpointPeriodStart = nextCheckpoint - (BASE_CHECKPOINT_MULTIPLIER - _reduction) * BASE_CHECKPOINT_DURATION;

        emit CheckpointSet(user, nextCheckpoint);
        return (missedPeriod, checkpointPeriodStart, nextCheckpoint);
    }

    function _postponeCheckpointFromCurrentTimestamp(address user) internal returns (uint256) {
        // this does not postpone using the previous checkpoint as a starting point, but the current timestamp
        // It's onlhy meant to be used by relock()
        uint256 newCheckpoint = block.timestamp + _checkpointMultiplier(user) * BASE_CHECKPOINT_DURATION;
        checkpoint[user] = newCheckpoint;
        emit CheckpointSet(user, newCheckpoint);
        return newCheckpoint;
    }

    function _initCheckpoint(address user) internal {
        uint256 userCheckpoint = block.timestamp + _checkpointMultiplier(user) * BASE_CHECKPOINT_DURATION;
        checkpoint[user] = userCheckpoint;
        emit CheckpointSet(user, userCheckpoint);
    }

    function _resetCheckpointInfo(address _user) internal {
        // either of the following variables can be used to identify a 'finished' stakeholder
        delete checkpoint[_user];
        // deleting the checkpointMultiplierReduction will also remove the superstaker status
        delete checkpointMultiplierReduction[_user];
        emit CheckpointSet(_user, 0);
    }

    /// @dev    The condition for being a super staker is to have crossed at least one checkpoint
    function _isSuperstaker(address user) internal view returns (bool) {
        return checkpointMultiplierReduction[user] > 0;
    }

    function _canCrossCheckpoint(address user) internal view returns (bool) {
        // only allows existing users
        return (checkpoint[user] != 0) && (block.timestamp > checkpoint[user]);
    }
}
