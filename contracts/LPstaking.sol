// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

/**
 * @title  Simple staking pool for LP tokens
 * @author VINCI
 * @notice This contract is meant to be used to incentivise liquidity provision by distributing Vinci.
 */
contract VinciLPStaking is AccessControl {
    bytes32 public constant CONTRACT_OPERATOR_ROLE = keccak256("CONTRACT_OPERATOR_ROLE");

    using SafeERC20 for ERC20;

    /// vinci contract
    ERC20 private immutable vinciToken;

    /// LP contract (given after liquidity pool is created)
    ERC20 private immutable lpToken;

    struct Stake {
        // uint128 is enough and allows for struct packing (gas savings)
        uint128 releaseTime;
        uint64 monthsLocked;
        bool withdrawn;
        uint256 amount;
        uint256 claimedWeeklyVinciRewardsPerLP;
        uint256 claimedFinalVinciRewardsPerLP;
    }

    // Vinci per LP token. How many Vinci do I get for one (complete) LP token
    // Vinci comes with all decimals, while LP does not
    uint256 public LPpriceInVinci;

    // stakings of each user are stored as an array of Stake structs
    mapping(address => Stake[]) public stakes;

    /// Remaining VINCI tokens used exclusively for staking rewards
    uint256 public fundsForStakingRewards;
    uint256 public fundsForInstantPayouts;

    /// total staked LP tokens in the contract. This is used everytime the distributeAPR() is called (weekly)
    uint256 public totalStakedLPTokens;
    // number of APR distributions. We keep track of this in case we miss a week, that rewards are not lost
    uint256 internal numberOfDistributionsCompleted;
    // If the division of the totalStakedLPTokens and the weekly rewards is not exact, we buffer the decimals
    uint256 public bufferedDecimals;

    // This is how many VINCI tokens corresponds to one LP token in terms of rewards.
    // This will be constantly updated every time the APR is distributed
    // Deppending on the number of months locked, the rewards will be split differently between weekly and final payouts
    uint256 vinciRewardsPerLP;
    // Used for all calculations that need percentages and shares (payouts)
    uint256 internal constant BASIS_POINTS = 10000;

    uint256 public WEEKLY_VINCI_REWARDS = 153_846_154 ether;

    // We use a reference time to track the number of weeks since inception
    // We hardcode the launch date as the reference time is: 31 May 2023 02:00:00 GMT+02:00.
    // TODO: review this reference time if the launch date is postponed
    uint256 public constant rewardsReferenceStartingTime = 1685491200;

    event Staked(address indexed staker, uint256 _amount, uint64 _monthsLocked);
    event Unstaked(address indexed staker, uint256 _amount);
    event APRDistributed(uint256 _distributionCounter, uint256 vinciDistributed);
    event NonClaimedRewardsReceived(address indexed staker, uint256 _missingClaims);
    event InstantPayoutInVinci(address indexed staker, uint256 _amount);
    event FundedInstantPayoutsBalance(address indexed staker, uint256 _amount);
    event FundedStakingRewardsBalance(address indexed staker, uint256 _amount);
    event InsufficientVinciForInstantPayout(address indexed staker, uint256 correspondingPayout, uint256 missedPayout);
    event RewardsClaimReceived(address indexed staker, uint256 _amount);
    event NotVinciFundsToDistributeAPR();

    error APRDistributionTooSoon();
    error UnsupportedNumberOfMonths();
    error InvalidAmount();
    error NonExistingIndex();
    error StakeNotReleased();
    error AlreadyWithdrawnIndex();
    error NoLpTokensStaked();
    error NoRewardsToClaim();
    error InsufficientVinciInLPStakingContract();

    /**
     * @dev   Create a new VinciLPStaking
     * @param vinciContract The address of the Vinci Contract on this chain
     * @param lpContract    The address of a ERC20 compatible contract used as a staking token. This can be a LP token.
     */
    constructor(ERC20 vinciContract, ERC20 lpContract) {
        vinciToken = vinciContract;
        lpToken = lpContract;

        // initially the deployer has both roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(CONTRACT_OPERATOR_ROLE, msg.sender);
    }

    // @notice Create a new stake with `monthsLocked` months that is supposed to be locked.
    function newStake(uint256 amount, uint64 monthsLocked) external {
        if ((monthsLocked != 4) && (monthsLocked != 8) && (monthsLocked != 12)) revert UnsupportedNumberOfMonths();
        if (amount == 0) revert InvalidAmount();
        address sender = msg.sender;

        // monthsLocked is already capped by uint64 so should be safe of overloads
        uint128 releaseTime = uint64(block.timestamp) + (30 days * monthsLocked);
        // here, the weekly and final are tracked as the same value. It is the responsibility of _getCurrentClaimable()
        // to make the distinction between weekly and final for the different months locked, to make sure amounts are
        // not double counted
        stakes[sender].push(Stake(releaseTime, monthsLocked, false, amount, vinciRewardsPerLP, vinciRewardsPerLP));

        // these are used to calculate APR rewards
        totalStakedLPTokens += amount;

        // For low amount of LP tokens this Division will return 0 due to lack of decimals in solidity. No payout
        uint256 vinciInstantPayout = (amount * LPpriceInVinci * _instantPayoutMultiplier(monthsLocked))
            / (10 ** lpToken.decimals() * BASIS_POINTS);

        if (vinciInstantPayout > fundsForInstantPayouts) {
            uint256 missedPayout = vinciInstantPayout - fundsForInstantPayouts;
            emit InsufficientVinciForInstantPayout(sender, vinciInstantPayout, missedPayout);
            vinciInstantPayout = fundsForInstantPayouts;
        }

        // instant payout is available First-come-first-serve. But after that, staking is still possible
        emit InstantPayoutInVinci(sender, vinciInstantPayout);
        if (vinciInstantPayout > 0) {
            fundsForInstantPayouts -= vinciInstantPayout;
            vinciToken.safeTransfer(sender, vinciInstantPayout);
        }

        emit Staked(sender, amount, monthsLocked);
        lpToken.safeTransferFrom(sender, address(this), amount);
    }

    /// @notice Claim staking rewards from a stake. Each stake has to be claimed separately
    function claimRewards(uint256 stakeIndex) external {
        address sender = msg.sender;
        if (stakes[sender][stakeIndex].withdrawn) revert AlreadyWithdrawnIndex();

        uint256 claimableNow = _getCurrentClaimable(sender, stakeIndex);
        if (claimableNow == 0) revert NoRewardsToClaim();

        // resets the rewards trackers to the current vinci RewardsPerLP
        stakes[sender][stakeIndex].claimedWeeklyVinciRewardsPerLP = vinciRewardsPerLP;
        // The final is only reset if the claim happens with a released stake.
        if (stakes[sender][stakeIndex].releaseTime < block.timestamp) {
            stakes[sender][stakeIndex].claimedFinalVinciRewardsPerLP = vinciRewardsPerLP;
        }

        _sendStakingRewards(sender, claimableNow);
        emit RewardsClaimReceived(sender, claimableNow);
    }

    /// @notice Withdraw a staked amount after the lock time has expired
    function withdrawStake(uint256 stakeIndex) external {
        address sender = msg.sender;

        if (stakeIndex > stakes[sender].length - 1) revert NonExistingIndex();
        if (stakes[sender][stakeIndex].withdrawn) revert AlreadyWithdrawnIndex();
        if (stakes[sender][stakeIndex].releaseTime > block.timestamp) revert StakeNotReleased();

        uint256 stakedLPAmount = stakes[sender][stakeIndex].amount;
        uint256 missingClaims = _getCurrentClaimable(sender, stakeIndex);

        // Here we avoid future reward claims and double withdrawns
        stakes[sender][stakeIndex].claimedWeeklyVinciRewardsPerLP = vinciRewardsPerLP;
        stakes[sender][stakeIndex].claimedFinalVinciRewardsPerLP = vinciRewardsPerLP;
        stakes[sender][stakeIndex].withdrawn = true;

        totalStakedLPTokens -= stakedLPAmount;

        emit Unstaked(sender, stakedLPAmount);
        lpToken.safeTransfer(sender, stakedLPAmount);

        if (missingClaims > 0) {
            _sendStakingRewards(sender, missingClaims);
        }
        emit NonClaimedRewardsReceived(sender, missingClaims);
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // Management functions

    /// @notice Set the amount of vinci equivalent to an LP token.
    ///         Decimals need to be the decimals of the Vinci Token.
    ///         I.e. If the price of an LP is 0.2 VINCI,
    ///         the amount to input should be 0.2 * (10 ** <decimals of Vinci>).
    function setLPPriceInVinci(uint256 _newPrice) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        LPpriceInVinci = _newPrice;
    }

    /// @notice Set the amount of vinci rewards that are distributed weekly among all stakes from now onwards
    function setWeeklyRewards(uint256 newWeeklyVinciRewards) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        WEEKLY_VINCI_REWARDS = newWeeklyVinciRewards;
    }

    /// @notice Enables Vinci deposits to the contract, to be used exclusively for instant payouts
    function addVinciForInstantPayouts(uint256 amount) external {
        fundsForInstantPayouts += amount;
        emit FundedInstantPayoutsBalance(msg.sender, amount);
        vinciToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Enables Vinci deposits to the contract, to be used exclusively for staking rewards
    function addVinciForStakingRewards(uint256 amount) external {
        fundsForStakingRewards += amount;
        emit FundedStakingRewardsBalance(msg.sender, amount);
        vinciToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev    even though VINCI will take care of calling this function, any wallet could do it
    function distributeWeeklyAPR() external {
        uint256 _buffered = bufferedDecimals;
        if (fundsForStakingRewards < WEEKLY_VINCI_REWARDS + _buffered) revert InsufficientVinciInLPStakingContract();

        // Save totalStaked to save gas
        uint256 totalStaked = totalStakedLPTokens;
        if (totalStaked == 0) revert NoLpTokensStaked();

        // we track the number of weeks since the reference date
        // this way of tracking APR distributions allows for two in a row if we miss one
        uint256 targetDistributions = (block.timestamp - rewardsReferenceStartingTime) / (1 weeks);
        if (numberOfDistributionsCompleted >= targetDistributions) revert APRDistributionTooSoon();

        // This controls how much vinci per LP token
        uint256 weeklyVinciDistribution = WEEKLY_VINCI_REWARDS + _buffered;
        uint256 rewardsPerLPToken = weeklyVinciDistribution / totalStaked;
        bufferedDecimals = weeklyVinciDistribution % totalStaked;
        numberOfDistributionsCompleted += 1;

        if (rewardsPerLPToken == 0) {
            emit NotVinciFundsToDistributeAPR();
            return;
        }

        // here we add it to both
        vinciRewardsPerLP += rewardsPerLPToken;
        // keep track of spent funds in rewards
        fundsForStakingRewards -= rewardsPerLPToken * totalStaked;

        emit APRDistributed(numberOfDistributionsCompleted, rewardsPerLPToken * totalStaked);
    }

    /// ==================================================================
    ///                         READ FUNCTIONS
    /// ==================================================================

    // @notice returns the total amount staked by a user, accounting for all stakes
    function getUserTotalStaked(address staker) external view returns (uint256) {
        uint256 totalStaked;
        uint256 nStakes = stakes[staker].length;
        for (uint256 index = 0; index < nStakes; index++) {
            totalStaked += stakes[staker][index].amount;
        }
        return totalStaked;
    }

    // @notice returns the current claimable rewards generated by one stake
    function readCurrentClaimable(address staker, uint256 stakeIndex) external view returns (uint256) {
        return _getCurrentClaimable(staker, stakeIndex);
    }

    // @notice returns the current claimable rewards generated by all stakes
    function readTotalCurrentClaimable(address staker) external view returns (uint256) {
        uint256 total;
        uint256 nStakes = stakes[staker].length;
        for (uint256 index = 0; index < nStakes; index++) {
            total += _getCurrentClaimable(staker, index);
        }
        return total;
    }

    /// @notice returns the amount of vinci from a single stake  that will be available for claim once it is released
    /// @dev    If the stake has been already withdrawn, it returns 0
    function readFinalPayout(address staker, uint256 stakeIndex) external view returns (uint256) {
        if (stakes[staker][stakeIndex].withdrawn) return 0;
        return _finalMultiplier(stakes[staker][stakeIndex].monthsLocked) * stakes[staker][stakeIndex].amount
            * (vinciRewardsPerLP - stakes[staker][stakeIndex].claimedFinalVinciRewardsPerLP) / BASIS_POINTS;
    }

    // @notice returns the amount of times the user has executed newStake()
    function getNumberOfStakes(address owner) external view returns (uint256) {
        return stakes[owner].length;
    }

    // @notice returns the amount staked in a particular stake
    function getStakeAmount(address owner, uint256 stakeIndex) external view returns (uint256) {
        return stakes[owner][stakeIndex].amount;
    }

    // @notice returns the time when a particular stake will be released (and become claimable)
    function getStakeReleaseTime(address owner, uint256 stakeIndex) external view returns (uint128) {
        return stakes[owner][stakeIndex].releaseTime;
    }

    // @notice returns the number of months a stake was locked
    function getStakeMonthsLocked(address owner, uint256 stakeIndex) external view returns (uint64) {
        return stakes[owner][stakeIndex].monthsLocked;
    }

    // @notice returns true if a particular stake has been already withdrawn
    function isWithdrawn(address staker, uint256 stakeIndex) external view returns (bool) {
        return stakes[staker][stakeIndex].withdrawn;
    }

    /// @dev    This allows to read the entire Stake struct instead of individual fields
    function readStake(address staker, uint256 stakeIndex) external view returns (Stake memory) {
        return stakes[staker][stakeIndex];
    }

    ///////////////////////////////////////////////////////////////////////////////////////////
    // internal functions

    function _getCurrentClaimable(address staker, uint256 stakeIndex) internal view returns (uint256) {
        // save stake in memory to save gas
        Stake memory stake = stakes[staker][stakeIndex];

        if (stake.withdrawn) {
            return 0;
        }

        uint256 claimable;
        if (_weeklyMultiplier(stake.monthsLocked) > 0) {
            claimable += stake.amount * (vinciRewardsPerLP - stake.claimedWeeklyVinciRewardsPerLP)
                * _weeklyMultiplier(stake.monthsLocked) / BASIS_POINTS;
        }
        // if the stake is unlocked, the final payout is also claimable
        if ((_finalMultiplier(stake.monthsLocked) > 0) && (stake.releaseTime < block.timestamp)) {
            claimable += stake.amount * (vinciRewardsPerLP - stake.claimedFinalVinciRewardsPerLP)
                * _finalMultiplier(stake.monthsLocked) / BASIS_POINTS;
        }
        return claimable;
    }

    function _sendStakingRewards(address to, uint256 amount) internal {
        // There should always be enough funds to pay the rewards, because the distributeAPR function only distributes
        // if there are funds available
        vinciToken.safeTransfer(to, amount);
    }

    function _instantPayoutMultiplier(uint256 monthsLocked) internal pure returns (uint256) {
        // hardcoded these values to save gas
        if (monthsLocked == 4) {
            // 0.5 %
            return 50;
        } else if (monthsLocked == 8) {
            // 1.5 %
            return 150;
        } else {
            // 5 %
            return 500;
        }
    }

    function _weeklyMultiplier(uint256 monthsLocked) internal pure returns (uint256) {
        // hardcoded these values to save gas
        if (monthsLocked == 4) {
            // nmonths=4 --> all APR given at the end
            return 0;
        } else if (monthsLocked == 8) {
            // nmonths=8 --> 50% APR given on a weekly basis, 50% at the end
            return 5000;
        } else {
            // nmonths=12 --> all APR given on a weekly basis
            return 10000;
        }
    }

    function _finalMultiplier(uint256 monthsLocked) internal pure returns (uint256) {
        // hardcoded these values to save gas
        if (monthsLocked == 4) {
            // nmonths=4 --> all APR given at the end
            return 10000;
        } else if (monthsLocked == 8) {
            // nmonths=8 --> 50% APR given on a weekly basis, 50% at the end
            return 5000;
        } else {
            // nmonths=12 --> all APR given on a weekly basis
            return 0;
        }
    }
}
