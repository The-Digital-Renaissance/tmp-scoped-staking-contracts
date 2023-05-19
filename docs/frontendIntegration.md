# Frontend Integration 

## VinciStakingV1

Contracts from which the information are retrieved:

- `contracts/vinciToken.sol: Vinci`
- `contracts/vinciStaking.sol: VinciStakingV1`
- `contracts/LPstaking.sol: VinciLPStaking`

For more detailed explanation of the function and the input arguments, please 
refer to the interface in:
- `interfaces/IVinciStaking.sol: IVinciStaking`.

### Personal Dashboard view

#### Timeline
- Lanuch date: `31st may`
- Days Staked: `vinciStakingV1.getDaysStaked(user)` . With this you have the length of the purple bar. 
- Superstaker status is granted when crossing the checkpoint 1.
- The location of the checkpoints is: 6 months from streak start, then 5 months, then 4 months ... until 1 month, and then 1 month every time


#### Overview
- Total stake: `vinciStakingV1.activeStaking(user)`
- Unvested rewards: `vinciStakingV1.getTotalUnclaimableBalance(user)`
  - From pre-staking bonus == from airdrops: `vinciStakingV1.getUnclaimableFromAirdrops(user)`
  - From penalty pot: `vinciStakingV1.getUnclaimableFromPenaltyPot(user)`
  - From staking rewards: `vinciStakingV1.getUnclaimableFromBaseApr(user)`
- Vested rewards: `vinciStakingV1.claimableBalance(user)`
- claimed rewards: hardcode it to 0 for now. Nobody can claim before the first 6 months. Future update: query all the `Claimed(user,amount)` events for the specific `user` and add up all the `amounts`.  


#### Quick Reward Overview
- Prestake bonus: == from airdrops: `vinciStakingV1.getUnclaimableFromAirdrops(user)`
- Current APR: `rewards * YearDuration / (activeStaking * stakeDuration)`
  - `rewards` = `vinciStakingV1.getTotalUnclaimableBalance(user)`
  - `YearDuration` = 365 * 24 * 3600 (seconds)
  - `activeStaking` = `vinciStakingV1.activeStaking(user)`
  - `stakeDuration` = `vinciStakingV1.getDaysStaked(user)`
- Days Staked: `vinciStakingV1.getDaysStaked(user)`
- Next rewards update: **[THIS FIELD SHOULD DISAPPEAR]**

### Staking 
#### why should I stake

- Current Staking ARP: Extremely inefficient to calculate this in the contract. We should calculate offline and hardcode it, or put it in firebase or somewhere
- Vinci staked: `vinciStakingV1.totalVinciStaked(user)`
- Unique wallets staked: [REMOVE FIELD]
- Total Vinci Staked: = `totalStaked / circulating Supply`
  - TODO: circulating supply could be get from coingecko, but we don't want to wait for that... perhaps we can just hardcode it

### Token Allocation
#### Token Allocation
This one interacts with a different contract, with the token contract: VinciToken. 

- Unlocked: 
  - From Pre-sale: `ViniciToken.getTotalUnVestedTokens(user)`
  - Other: [REMOVE FIELD]
- Locked: 
  - From Pre-sale: `ViniciToken.getTotalVestedTokens(user)`
  - Other: [REMOVE FIELD]


#### Vesting Release
1. You need to query first how many "releases are scheduled": `vinciToken.getNumberOfTimelocks(user)`. With this, you will know how many boxes to display. You will probably need a side-scrollable window for this, because sometimes there are 12 months-unlocks 

2. You can query each of the releases, where `index=[0, numberOfReleases)`. Each of them will return the TimeLock objects with the following fields:
  - `readTimelock(user, index)`:
    - `amount`: the amount of tokens that will be released
    - `releaseTime`: the timestamp when the tokens will be released
    - `claimed`: bool, if True, it has already been claimed

To know if the amount is released and can be claim, the current timestamp must be higher than releaseTime.

#### Vesting Status timeline
- Vested: `ViniciToken.getTotalVestedTokens(user)`
- Unvested: `ViniciToken.getTotalUnVestedTokens(user)`
- Total claimed: `ViniciToken.getTotalClaimed(user)`

### LP dashboard

#### Overview

This dashboard has first an overview with only two values:
- Total Value locked: `VinciLPStaking.getUserTotalStaked(user)`
- Unvested rewards: `VinciLPStaking.readTotalCurrentClaimable(user)`

And then a list o f stakes, of unknown length. Each row shows information of a stake. The info of a Stake can be read with:
- `vinciLPStaking.readStake(user, index)`, with index=[0, numberOfStakes)
  - `uint128 releaseTime`; 
  - `uint64 monthsLocked`; 
  - `bool withdrawn`; 
  - `uint256 amount`; 
  - `uint256 weeklyVinciRewardsPerLPclaimed`; 
  - `uint256 finalVinciRewardsPerLPclaimed`;
  This will be returned as a tuple, so simply select the indexes that you need:
- LP tokens: `stake.amount`:
- Locked Since: `stake.releaseTime - stake.monthsLocked * 30 days`
- Finish date: `stake.releaseTime`

