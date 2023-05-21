// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./inheritables/tiers.sol";
import "./inheritables/checkpoints.sol";
import "./inheritables/penaltyPot.sol";

//                          &&&&&%%%%%%%%%%#########*
//                      &&&&&&&&%%%%%%%%%%##########(((((
//                   @&&&&&&&&&%%%%%%%%%##########((((((((((
//                @@&&&&&&&&&&%%%%%%%%%#########(((((((((((((((
//              @@@&&&&&&&&%%%%%%%%%%##########((((((((((((((///(
//            %@@&&&&&&               ######(                /////.
//           @@&&&&&&&&&           #######(((((((       ,///////////
//          @@&&&&&&&&%%%           ####((((((((((*   .//////////////
//         @@&&&&&&&%%%%%%          ##((((((((((((/  ////////////////*
//         &&&&&&&%%%%%%%%%          *(((((((((//// //////////////////
//         &&&&%%%%%%%%%####          .((((((/////,////////////////***
//        %%%%%%%%%%%########.          ((/////////////////***********
//         %%%%%##########((((/          /////////////****************
//         ##########((((((((((/          ///////*********************
//         #####((((((((((((/////          /*************************,
//          #(((((((((////////////          *************************
//           (((((//////////////***          ***********************
//            ,//////////***********        *************,*,,*,,**
//              ///******************      *,,,,,,,,,,,,,,,,,,,,,
//                ******************,,    ,,,,,,,,,,,,,,,,,,,,,
//                   ****,,*,,,,,,,,,,,  ,,,,,,,,,,,,,,,,,,,
//                      ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
//                          .,,,,,,,,,,,,,,,,,,,,,,,

/// @title Version 1 of Vinci staking pool
/// @notice A smart contract to handle staking of Vinci ERC20 token and grant Picasso club tiers and superstaker status
/// @dev The correct functioning of the contract having a positive funds for staking rewards
contract VinciStakingV1 is AccessControl, TierManager, Checkpoints, PenaltyPot {
    bytes32 public constant CONTRACT_OPERATOR_ROLE = keccak256("CONTRACT_OPERATOR_ROLE");
    bytes32 public constant CONTRACT_FUNDER_ROLE = keccak256("CONTRACT_FUNDER_ROLE");

    using SafeERC20 for IERC20;

    // balances
    uint256 public vinciStakingRewardsFunds;
    // Tokens that are staked and actively earning rewards
    mapping(address => uint256) public activeStaking;
    // Tokens that have been unstaked, but are not claimable yet (2 weeks delay)
    mapping(address => uint256) public currentlyUnstakingBalance;
    // Timestamp when the currentlyUnstakingBalance is available for claim
    mapping(address => uint256) public unstakingReleaseTime;
    // Total vinci rewards at the end of the current staking period of each user
    mapping(address => uint256) public fullPeriodAprRewards;
    // Airdropped tokens of each user. They are unclaimable until crossing the next period
    mapping(address => uint256) public airdroppedBalance;
    // Tokens that have been unlocked in previous checkpoints and are now claimable
    mapping(address => uint256) public claimableBalance;

    // constants
    uint256 public constant UNSTAKING_LOCK_TIME = 14 days;
    uint256 public constant BASE_APR = 550; // 5.5%
    uint256 public constant BASIS_POINTS = 10000;

    event Staked(address indexed user, uint256 amount);
    event UnstakingInitiated(address indexed user, uint256 amount);
    event UnstakingCompleted(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event AirdroppedBatch(address[] users, uint256[] amounts);
    event StakingRewardsFunded(address indexed funder, uint256 amount);
    event NonAllocatedStakingRewardsFundsRetrieved(address indexed funder, uint256 amount);
    event MissedRewardsPayout(address indexed user, uint256 entitledPayout, uint256 actualPayout);
    event MissedRewardsAllocation(address indexed user, uint256 entitledPayout, uint256 actualPayout);
    event StakingRewardsAllocated(address indexed user, uint256 amount);
    event StakeholderFinished(address indexed user);
    event Relocked(address indexed user);
    event CheckpointCrossed(address indexed user);
    event NotifyCannotCrossCheckpointYet(address indexed user);

    error NothingToClaim();
    error NothingToWithdraw();
    error InvalidAmount();
    error CannotCrossCheckpointYet();
    error NonExistingStaker();
    error UnstakedAmountNotReleasedYet();
    error NotEnoughStakingBalance();
    error ArrayTooLong();
    error CantRelockBeforeCrossingCheckpoint();
    error CheckpointHasToBeCrossedFirst();

    // Aggregation of all VINCI staked in the contract by all stakers
    uint256 public totalVinciStaked;

    /// ERC20 vinci token
    IERC20 public immutable vinciToken;

    constructor(ERC20 _vinciTokenAddress, uint128[] memory _tierThresholdsInVinci)
        TierManager(_tierThresholdsInVinci)
    {
        vinciToken = IERC20(_vinciTokenAddress);

        // note that the deployer of the contract is automatically granted the DEFAULT_ADMIN_ROLE but not CONTRACT_FUNDER_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTRACT_OPERATOR_ROLE, msg.sender);
    }

    /// ================== User functions =============================

    /// @dev Stake VINCI tokens to the contract
    function stake(uint256 amount) external {
        _stake(msg.sender, amount);
    }

    /// @dev Contract operator can stake tokens on behalf of users
    function batchStakeTo(address[] calldata users, uint256[] calldata amounts)
        external
        onlyRole(CONTRACT_OPERATOR_ROLE)
    {
        require(users.length == amounts.length, "Input lengths must match");
        // This is gas inefficient, as the ERC20 transaction takes place for every stake, instead of grouping the
        // total amount and making a single transfer. However, this function is meant to be used only once at the
        // beginning and the saved gas  doesn't compensate the added contract complexity
        for (uint256 i = 0; i < amounts.length; i++) {
            _stake(users[i], amounts[i]);
        }
    }

    /// @dev Unstake VINCI tokens from the contract
    function unstake(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        // unstaking has a high cost in this echosystem:
        // - loosing already earned staking rewards,
        // - being downgraded in tier
        // - a lockup of 2 weeks before the unstake can be completed
        // - potentially losing your staking streak if too much is unstaked
        address sender = msg.sender;
        // when unstaking, a percentage of the rewards, proportional to the current stake will be withdrawn as a penalty
        // from all the difference rewards sources: baseAPR, airdrops, penaltyPot.
        // This penalty is distributed to the penalty pot
        uint256 stakedBefore = activeStaking[sender];
        if (amount > stakedBefore) revert NotEnoughStakingBalance();
        // force users to cross checkpoint if timestamp allows it to avoid undesired contract states
        uint256 _checkpoint = checkpoint[sender];
        if (block.timestamp > _checkpoint) revert CheckpointHasToBeCrossedFirst();
        uint256 _userFullPeriodRewards = fullPeriodAprRewards[sender];
        // These rewards are rounded up due to BASIS_POINTS. Rounding issues may arise from there
        uint256 earnedRewards =
            _getCurrentUnclaimableRewardsFromBaseAPR(stakedBefore, _checkpoint, _userFullPeriodRewards);
        // the ratio between the penalization to the fullperiod and the penalization to the earned rewards is the same
        // the earned rewards (_getCurrentUnclaimableRewardsFromBaseAPR()) is calculated using the full period
        // as a baseline. Therefore, updating the fullperiod rewards is enough to also update the earned rewards
        uint256 fullPeriodRewardsReduction = _userFullPeriodRewards * amount / stakedBefore;
        uint256 penaltyToEarnedRewards = earnedRewards * amount / stakedBefore;
        // This always holds: fullPeriodRewardsReduction >= penaltyToEarnedRewards
        uint256 toRewardsFund = fullPeriodRewardsReduction - penaltyToEarnedRewards;
        // fullPeriodRewardsReduction will always be lower than fullPeriodAprRewards[sender] because it is taken as a ratio
        fullPeriodAprRewards[sender] -= fullPeriodRewardsReduction;
        // of the penalizatoin to the fullPeriodAprRewards, the part corresponding to the earned rewards goes to the
        // penaltyPot, while the rest goes back to the rewards fund
        vinciStakingRewardsFunds += toRewardsFund;

        uint256 penaltyToAirdrops = airdroppedBalance[sender] * amount / stakedBefore;
        airdroppedBalance[sender] -= penaltyToAirdrops;

        uint256 penaltyToPenaltyPot = _penalizePenaltyPotShare(sender, amount, stakedBefore);

        uint256 totalPenalization = penaltyToEarnedRewards + penaltyToAirdrops + penaltyToPenaltyPot;

        if (_isSuperstaker(sender)) {
            // we only reduce the amount eligible for penaltyPotRewards if already a superstaker
            // no need to _bufferPenaltyPot here, as it is already done by _penalizePenaltyPotShare() above
            _removeFromEligibleSupplyForPenaltyPot(amount);
        }

        // It is OK that the penalized user also gets back a small fraction of its own penalty.
        // the fraction might not be so small if the staker is large ...
        _depositToPenaltyPot(totalPenalization);

        // modify these ones only after the modifications to penalty pot
        totalVinciStaked -= amount;
        activeStaking[sender] -= amount;
        currentlyUnstakingBalance[sender] += amount;
        unstakingReleaseTime[sender] = block.timestamp + UNSTAKING_LOCK_TIME;

        // in case of unstaking all the amount, the user looses tier, checkpoint history etc
        if (amount == stakedBefore) {
            // finished stakeholders can still claim pending claims or pending unstaking tokens
            _setTier(sender, 0);
            // deleting the checkpointMultiplierReduction will also remove the superstaker status
            _resetCheckpointInfo(sender);
            emit StakeholderFinished(sender);
        } else {
            uint256 currentTier = userTier[sender];
            // if current tier is 0, there is no need to update anything as it can only be downgraded
            if ((currentTier > 0) && (thresholds[currentTier - 1] > stakedBefore - amount)) {
                _setTier(sender, _calculateTier(stakedBefore - amount));
            }
        }
        emit UnstakingInitiated(sender, amount);
    }

    /// @notice Function to claim rewards in the claimable balance
    function claim() external {
        // finished stakeholders should also be able to claim their tokens also after being finished as stakeholders
        address sender = msg.sender;

        uint256 amount = claimableBalance[sender];
        if (amount == 0) revert NothingToClaim();

        delete claimableBalance[sender];
        emit Claimed(sender, amount);
        _sendVinci(sender, amount);
    }

    /// @notice Function to withdraw unstaked tokens, only after the lockup period has passed
    function withdraw() external {
        // finished stakeholders should also be able to withdraw their tokens also after being finished as stakeholders
        address sender = msg.sender;

        if (block.timestamp < unstakingReleaseTime[sender]) revert UnstakedAmountNotReleasedYet();

        uint256 amount = currentlyUnstakingBalance[sender];
        if (amount == 0) revert NothingToWithdraw();

        // delele storage variables to get gas refund
        delete currentlyUnstakingBalance[sender];
        delete unstakingReleaseTime[sender];
        emit UnstakingCompleted(sender, amount);
        _sendVinci(sender, amount);
    }

    /// @notice Function to relock the stake, which will reevaluate tier and postpone the checkpoint by the same amount
    ///         of months as the current period
    function relock() external {
        address sender = msg.sender;
        if (!_existingUser(sender)) revert NonExistingStaker();
        if (_canCrossCheckpoint(sender)) revert CantRelockBeforeCrossingCheckpoint();

        uint256 staked = activeStaking[sender];
        uint256 previousNextCheckpoint = checkpoint[sender];

        _setTier(sender, _calculateTier(staked));
        uint newCheckpoint = _postponeCheckpointFromCurrentTimestamp(sender);

        // extend the baseAprBalanceNextCP with the length from current next checkpoint until new next checkpoint
        // if checkpoing[sender] < previousNextCheckpoint, tx would revert above due to _canCrossCheckpoint() = true
        uint256 extraRewards = _estimatePeriodRewards(staked, newCheckpoint - previousNextCheckpoint);
        uint256 currentFunds = vinciStakingRewardsFunds;
        if (extraRewards > currentFunds) {
            emit MissedRewardsAllocation(sender, extraRewards, currentFunds);
            extraRewards = currentFunds;
        }
        if (extraRewards > 0) {
            fullPeriodAprRewards[sender] += extraRewards;
            vinciStakingRewardsFunds -= extraRewards;
        }

        emit Relocked(sender);
    }

    /// @notice Allows a user to cross the checkpoint, and turn all the unvested rewards into claimable rewards
    function crossCheckpoint() external {
        if (!_canCrossCheckpoint(msg.sender)) revert CannotCrossCheckpointYet();
        _crossCheckpoint(msg.sender);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /// Contract Management Functions

    function distributePenaltyPot() external onlyRole(CONTRACT_OPERATOR_ROLE) {
        _distributePenaltyPot();
    }

    /// @notice Allows the contract operator to cross the checkpoint in behalf of a user
    function crossCheckpointTo(address[] calldata to) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        if (to.length > 250) revert ArrayTooLong();
        // here we don't revert if one of them cannot cross, we simply skip it but throw an event
        for (uint256 i = 0; i < to.length; i++) {
            if (_canCrossCheckpoint(to[i])) {
                _crossCheckpoint(to[i]);
            } else {
                emit NotifyCannotCrossCheckpointYet(to[i]);
            }
        }
    }

    /// @notice Allows airdropping vinci to multiple current stakers. IMPORTANT: if any address is not a current
    ///         staker, the whole transaction will revert. All addresses must have an active staking at the time of the
    ///         airdrop.
    function batchAirdrop(address[] calldata users, uint256[] calldata amount)
        external
        onlyRole(CONTRACT_OPERATOR_ROLE)
    {
        if (users.length != amount.length) revert("Lengths must match");
        uint256 n = users.length;

        uint256 total;
        for (uint256 i = 0; i < n; i++) {
            require(_existingUser(users[i]), "Users must have active stake to receive airdrops");
            airdroppedBalance[users[i]] += amount[i];
            total += amount[i];
        }

        emit AirdroppedBatch(users, amount);
        _receiveVinci(total);
    }

    // only the vinci team can fund the staking rewards, because they can retrieve it later
    function fundContractWithVinciForRewards(uint256 amount) external onlyRole(CONTRACT_FUNDER_ROLE) {
        if (amount == 0) revert InvalidAmount();
        vinciStakingRewardsFunds += amount;
        emit StakingRewardsFunded(msg.sender, amount);
        _receiveVinci(amount);
    }

    function removeNonAllocatedStakingRewards(uint256 amount) external onlyRole(CONTRACT_FUNDER_ROLE) {
        vinciStakingRewardsFunds -= amount;
        emit NonAllocatedStakingRewardsFundsRetrieved(msg.sender, amount);
        _sendVinci(msg.sender, amount);
    }

    //

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /// View functions

    /// @notice All unvested rewards that are not claimable yet. They can come from 3 different sources:
    ///         - airdoprs,
    ///         - corresponding share of the penaltyPot
    ///         - basic staking rewards (5.5% APR on the user's staking balance)
    function getTotalUnclaimableBalance(address user) public view returns (uint256) {
        uint256 stakingbalance = activeStaking[user];
        return airdroppedBalance[user] + _getAllocatedSharePenaltyPot(user, stakingbalance)
            + _getCurrentUnclaimableRewardsFromBaseAPR(stakingbalance, checkpoint[user], fullPeriodAprRewards[user]);
    }

    /// @notice Part of the unvested rewards that come from airdrops
    function getUnclaimableFromAirdrops(address user) external view returns (uint256) {
        return airdroppedBalance[user];
    }

    /// @notice Part of the unvested rewards that come from the basic staking rewards (5.5% on the staking balance)
    function getUnclaimableFromBaseApr(address user) external view returns (uint256) {
        return
            _getCurrentUnclaimableRewardsFromBaseAPR(activeStaking[user], checkpoint[user], fullPeriodAprRewards[user]);
    }

    /// @notice Part of the unvested rewards that are the user's share of the current penalty pot
    ///         This unclaimable does not account for the buffered decimals. These are 'postponed' until next distribution
    function getUnclaimableFromPenaltyPot(address user) external view returns (uint256) {
        return _getAllocatedSharePenaltyPot(user, activeStaking[user]);
    }

    /// @notice Estimates the unvested rewards comming from the penalty pot, including the tokens from the pot that
    ///         have not been distributed yet
    function estimatedShareOfPenaltyPot(address user) external view returns (uint256) {
        return _estimateUserShareOfPenaltyPot(user, activeStaking[user]);
    }

    /// @notice Returns the current supply eligible for penalty pot rewards
    function getSupplyEligibleForPenaltyPot() external view returns (uint256) {
        return _getSupplyEligibleForAllocation();
    }

    /// @notice When a user unstakes, those tokens are locked for 15 days, not earning rewards. Once the lockup period
    ///         ends, these toknes are available for withdraw. This function returns the amount of tokens available
    ///         for withdraw.
    function getUnstakeAmountAvailableForWithdrawal(address user) external view returns (uint256) {
        return (unstakingReleaseTime[user] > block.timestamp) ? 0 : currentlyUnstakingBalance[user];
    }

    /// @notice When a user unstakes, a penalization is imposed on the three different sources of unvested rewards.
    ///         This function returns what would be the potential loss (aggregation of the three sources)
    ///         This will help being transparent with the user and let them know how much they will lose if they
    ///         actually unstake
    function estimateRewardsLossIfUnstaking(address user, uint256 unstakeAmount) external view returns (uint256) {
        return getTotalUnclaimableBalance(user) * unstakeAmount / activeStaking[user];
    }

    /// @notice Total VINCI collected in the penalty pot from penalizations to unstakers
    function penaltyPot() external view returns (uint256) {
        return _getTotalPenaltyPot();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    /// @notice Timestamp of the next checkpoint for the user
    function nextCheckpointTimestamp(address user) external view returns (uint256) {
        return checkpoint[user];
    }

    /// @notice Duration in months of the current checkpoint period (it reduces every time a checkpoint is crossed)
    function currentCheckpointDurationInMonths(address user) external view returns (uint256) {
        return _checkpointMultiplier(user);
    }

    /// @notice Returns if the checkpoint information of `user` is up-to-date
    ///         If the user does not exist, it also returns true, as there is no info to be updated
    function canCrossCheckpoint(address user) external view returns (bool) {
        return _canCrossCheckpoint(user);
    }

    /// @notice Returns True if the user has earned the status of SuperStaker. This is gained once the user has
    ///         crossed at least one checkpoint with non-zero staking. The SuperStaker status is lost when all the
    ///          balance is unstaked
    function isSuperstaker(address user) external view returns (bool) {
        return _isSuperstaker(user);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////
    /// @notice Returns the minimum amount of VINCI to enter in `tier`
    function getTierThreshold(uint256 tier) external view returns (uint256) {
        return _tierThreshold(tier);
    }

    /// @notice Returns the number of current tiers
    function getNumberOfTiers() external view returns (uint256) {
        return _numberOfTiers();
    }

    /// @notice Returns the potential tier for a given `balance` of VINCI tokens if evaluated now
    function calculateTier(uint256 vinciBalance) external view returns (uint256) {
        return _calculateTier(vinciBalance);
    }

    /// @notice Updates the thresholds to access each tier
    function updateTierThresholds(uint128[] memory tierThresholds) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        _updateTierThresholds(tierThresholds);
    }

    function getUserTier(address user) external view returns (uint256) {
        return _getUserTier(user);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /// INTERNAL FUNCTIONS

    function _stake(address user, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();

        uint256 stakingBalance = activeStaking[user];

        if (stakingBalance == 0) {
            // initiate stakers that have never staked before (or they unstaked everything)
            _initCheckpoint(user);
            _setTier(user, _calculateTier(amount));
        } else if (_canCrossCheckpoint(user)) {
            revert CheckpointHasToBeCrossedFirst();
        } else if (_isSuperstaker(user)) {
            // no need to track the supplyEligibleForPenaltyPot specific of a user, because that is exactly the activeStaking
            // We only need to buffer any penalty pot earned so far, before changing the activeStaking
            _bufferPenaltyPotAllocation(user, stakingBalance);
            // This addition is not specific for the user, but for the entire penalty pot supply
            _addToEligibleSupplyForPenaltyPot(amount);
        }

        // we save the rewards for the entire period since now until next checkpoint here because they will only be
        // unlocked in the next checkpoint anyways
        uint256 rewards = _estimatePeriodRewards(amount, checkpoint[user] - block.timestamp);
        uint256 availableFunds = vinciStakingRewardsFunds;
        if (rewards > availableFunds) {
            // only one reading from storage to save gas
            emit MissedRewardsAllocation(user, rewards, availableFunds);
            rewards = availableFunds;
        } else {
            emit StakingRewardsAllocated(user, rewards);
        }

        activeStaking[user] += amount;
        totalVinciStaked += amount;
        fullPeriodAprRewards[user] += rewards;
        vinciStakingRewardsFunds -= rewards;

        emit Staked(user, amount);
        _receiveVinci(amount);
    }

    // @dev The callers of this function need to make sure that the checkpoint can be crossed
    function _crossCheckpoint(address user) internal {
        uint256 activeStake = activeStaking[user];
        uint256 penaltyPotShare = _isSuperstaker(user) ? _redeemPenaltyPot(user, activeStake) : 0;
        uint256 _rewardsFunds = vinciStakingRewardsFunds;

        uint256 claimableAddition = fullPeriodAprRewards[user] + airdroppedBalance[user] + penaltyPotShare;

        delete airdroppedBalance[user];

        // user will automatically become superStaker after the call to _postponeCheckpoint()
        if (!_isSuperstaker(user)) {
            _bufferPenaltyPotAllocation(user, 0);
            _addToEligibleSupplyForPenaltyPot(activeStake);
        }

        // we store newCheckpoint in memory to avoid reading it in the rest of this function (to save gas)
        (uint256 missedPeriod, uint256 currentPeriodStartTime, uint256 newCheckpoint) = _postponeCheckpoint(user);

        if (missedPeriod > 0) {
            // if the user missed a checkpoint, we need to allocate the rewards for the missed period
            // however, we need to update the rewardsPeriodStartTime to not double count the rewards
            uint256 missedRewards = _estimatePeriodRewards(activeStake, missedPeriod);
            // no need to be gas efficient here as this will happen very rarely
            if (missedRewards > _rewardsFunds) {
                // this is a missed PAYOUT because it goes directly into claimable
                emit MissedRewardsPayout(user, missedRewards, _rewardsFunds);
                missedRewards = _rewardsFunds;
            }

            // these missed rewards would go straight into claimable, as they come from old uncrossed checkpoints
            claimableAddition += missedRewards;
            _rewardsFunds -= missedRewards;
        }

        // only update storage variable if gt 0 to save gas
        if (claimableAddition > 0) {
            claimableBalance[user] += claimableAddition;
        }

        // set the rewards that will be accrued during the next period. Do this only after postponing checkpoint
        uint256 rewards = _estimatePeriodRewards(activeStake, newCheckpoint - currentPeriodStartTime);
        if (rewards > _rewardsFunds) {
            emit MissedRewardsAllocation(user, rewards, _rewardsFunds);
            rewards = _rewardsFunds;
        }
        // when there are no funds in the contract, the rewards allocated are smaller, and that means that the rewards
        // will be smaller over the entier period
        fullPeriodAprRewards[user] = rewards;
        _rewardsFunds -= rewards;

        // only update storage variable at the end with the new value after all modifications
        vinciStakingRewardsFunds = _rewardsFunds;

        // Evaluate new tier every time the checkpoint is crossed
        _setTier(user, _calculateTier(activeStake));
        emit CheckpointCrossed(user);
    }

    function _receiveVinci(uint256 amount) internal {
        vinciToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function _sendVinci(address to, uint256 amount) internal {
        vinciToken.safeTransfer(to, amount);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    /// Internal view/pure functions

    function _estimatePeriodRewards(uint256 amount, uint256 duration) internal pure returns (uint256) {
        // This should never ever happen, but we put this to avoid underflows
        return amount * BASE_APR * duration / (BASIS_POINTS * 365 days);
    }

    /// A user checkpoint=0 until the user is registered and it is set back to zero when is _finalized
    function _existingUser(address _user) internal view returns (bool) {
        return (checkpoint[_user] > 0) && (_user != address(0));
    }

    function _getCurrentUnclaimableRewardsFromBaseAPR(
        uint256 stakingBalance,
        uint256 _checkpoint,
        uint256 _userFullPeriodRewards
    ) internal view returns (uint256) {
        // This is tricky as the rewards schedule can change with stakes and unstakes from users. However:
        // we know the final rewards because that is the `baseAprBalance` and we know how much time until the next checkpoint
        // Therefore, the rewards earned so far are the total minus the ones not earned yet, that will be earned from
        // now until the next checkpoint
        if (stakingBalance == 0) return 0;
        // if checkpoint can be crossed already, the total APR is the one accumulated in the full period
        if (_checkpoint <= block.timestamp) return _userFullPeriodRewards;
        // block.timestamp is always < checkpoint[user] because otherwise it could cross checkpoint
        uint256 futureRewards = _estimatePeriodRewards(stakingBalance, _checkpoint - block.timestamp);
        // this subtraction can underflow due to rounding issues in _estimatePeriodRewards()
        return futureRewards > _userFullPeriodRewards ? 0 : _userFullPeriodRewards - futureRewards;
    }
}
