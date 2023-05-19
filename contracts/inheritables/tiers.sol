// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/AccessControl.sol";

error NonExistingTier();
error TooManyTiers();

contract TierManager is AccessControl {
    uint256 public constant MAX_NUMBER_OF_TIERS = 10;

    /// User tier which is granted according to the tier thresholds in vinci.
    /// Tiers are re-evaluated in certain occasions (unstake, relock, crossing a checkpoint)
    mapping(address => uint256) public userTier;

    // uint128 should be more than enough for the highest tier threshold at the lowest price possible
    uint128[] thresholds;

    event TiersThresholdsUpdated(uint128[] vinciThresholds);
    event TierSet(address indexed user, uint256 newTier);

    constructor(uint128[] memory _tierThresholdsInVinci) {
        _updateTierThresholds(_tierThresholdsInVinci);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // View functions

    /// @notice Returns the minimum amount of VINCI to enter in `tier`
    function _tierThreshold(uint256 tier) internal view returns (uint256) {
        if (tier == 0) return 0;
        if (tier > thresholds.length) revert NonExistingTier();
        return thresholds[tier - 1];
    }

    /// @notice Returns the number of current tiers
    function _numberOfTiers() internal view returns (uint256) {
        return thresholds.length;
    }

    /// @notice Returns the potential tier for a given `balance` of VINCI tokens if evaluated now
    function _calculateTier(uint256 vinciAmount) internal view returns (uint256 _tier) {
        if (thresholds.length == 0) revert("no tiers set");
        if (vinciAmount == 0) return 0;

        uint256 numberOfTiers = thresholds.length;
        uint256 tier = 0;
        for (uint256 i = 0; i < numberOfTiers + 1; i++) {
            if (tier == numberOfTiers) break;
            if (vinciAmount < thresholds[i]) break;
            tier += 1;
        }
        return tier;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Management functions

    /// @notice Allows to update the tier threholds in VINCI
    /// @dev    The contract owner will have execute this periodically to mimic the vinci price in usd for thresholds
    function _updateTierThresholds(uint128[] memory _tierThresholdsInVinci) internal {
        if (_tierThresholdsInVinci.length > MAX_NUMBER_OF_TIERS) revert TooManyTiers();
        require(_tierThresholdsInVinci.length > 0, "input at least one threshold");
        thresholds = _tierThresholdsInVinci;
        emit TiersThresholdsUpdated(_tierThresholdsInVinci);
    }

    // @dev Sets the tier for a given user
    function _setTier(address _user, uint256 _newTier) internal {
        if (_newTier != userTier[_user]) {
            userTier[_user] = _newTier;
            emit TierSet(_user, _newTier);
        }
    }
}
