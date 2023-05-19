# Vinci Staking - Implementation

The dev team has done its best to find a compromise between gas costs, decentralization, security and meeting the
requirements described in the [Staking Contract requirements](./vinciStakingRequirements.md):

## Implementation overview

The logic of the `VinciStakingV1.sol` inherits from three contracts that help splitting some logic:

- `checkpoints.sol` tracks the checkpoint related information
- `penaltyPot.sol` tracks the penalty pot related information
- `tier.sol` tracks the tier related information

This document attempts to give an overview of how the different functionalities from the requirements are implemented.

### Staking

- Staked tokens are tracked by the `activeStaking` mapping, which means that they are actively earning rewards.
- There are two functions that add tokens to the `activeStaking` balance of a user:
    - `stake()` executed by a user
    - `batchStakeTo()` excecuted by the contract operator to stake tokens to a number of addresses. From that point on,
      the
      receivers have full controll over their staked tokens.
- In the moment of staking, the APR rewards corresponding to the entire period are allocated to the user. Read more
  in [APR rewards](#apr-rewards) section

### APR rewards

- The contract needs to be funded with VINCI tokens that are used to pay staking rewards to stakers. This is tracked by
  the mapping `vinciStakingRewardsFunds` which can be funded by calling the method `fundContractWithVinciForRewards()`.
- When a user stakes, the allocated rewards to that user are taken from the `fundContractWithVinciForRewards` balance
  and added to the mapping `fullPeriodAprRewards`.
- As the rewards can only be retrieved on the next checkpoint, there is no need to constantly modify the rewards
  allocated on a weekly basis.
- If the user has some staking balance, it means it already has some rewards allocated. The new stake will simply add
  more rewards to that allocation that will be unvested at the end of the staking period. This extra allocation will
  only generate rewards for the remaining time until the checkpoint.
- Staking is only allowed if  `canCrossCheckpoint()` returns `false`. Read Checkpoints section.

### Airdrops

- The method `batchAirdrop()` allows the contract operator to airdrop rewards to selected users in batches to save gas.
- These unvested rewards are stored in the mapping `airdroppedBalance`.

### Unstaking

- With `unstake()` a user can unstake. The tokens are removed from `activeStaking` and added to `currentlyUnstaking`.
- This function takes care of penalizing the three rewards balances (from APR, from airdrops and from penalty pot) and
  add them to the penalty pot.
- The allocated APR rewards at the end of the period are modified in the same proportion as the ratio between the
  unstaked amount and the active staking balance.
    - From that reduction, the amount that has been already 'earned' (due to the lenght of the staking period) is added
      to the penalty pot. The reminding amount is added back to the `vinciStakingRewardsFunds`.
- The penalty from APR rewards, together with the penalty from airdrops and penalty pot are added to the penalty pot.
- If the user unstakes the entire staking balance, the user loses the Superstaker status, tier is reset to zero and the
  checkpoint system is also reset for the user.

### Penalty Pot

The penalty pot distribution needs to be done in a weighted among the Superstakers. This lead to the following
implementation:

- An internal supply tracks the total amount of VINCI tokens that are elegible to receive rewards from penalty pot
  distributions
- This supply is the sum of all staking balances of all users with the Superstaker status
- When a normal staker earns the Superstaker status, the staking balance is added to the elegible supply
- Every time a superstaker stakes or unstakes, the staking balance is added to the elegible supply.
- Periodically the vinci team will execute the function `distributePenaltyPot()` to distribute the penalty pot among the
  elegible users.
- The distribution is tracked with the 'number of vinci rewards allocated to each vinci
  staked' (`allocationPerStakedVinci`).
- When the distribution is triggered, it will divide the amount of tokens in the penalty pot by the elegible supply,
- and add them to `allocationPerStakedVinci`. The reminder of the division is stored in a buffer until the next
  distribution.
- The biggest challenge are the decimals in those divisions. For that, the elegible supply is tracked with only 3
  decimals. Because of this, some decimals would be lost with stakes/unstakes because of adding/removing tokens from the
  elegible supply with different amount of decimals. The decimals lost in these operations are stored
  in `bufferedDecimalsInSupplyAdditions` and `bufferedDecimalsInSupplySubtractions`. These decimals are added to the
  next additions/removals.
- Only when the `distributePenaltyPot()` function is called, the tokens in the penalty pot become allocated to the
  Superstakers, but they are allocated as unvested, and they can be lost if the Superstaker unstakes.
- Only the contract operator can execute `distributePenaltyPot()`.

### Checkpoints

The checkpoint system is a sensitive piece of the architecture, as it converts unvested rewards into vested rewards,
and allocates rewards of the following checkpoints and so on.

When a user stakes, the timestamp of the next checkpoint is set. However, it is not enough to pass that timestamp, but
also to execute the method `_crossCheckpoint()` to make the crossing effectively. Only by doing so the unvested rewards
are converted into vested rewards, the Superstatus can be granted and the tiers can be evaluated.

The vinci team will be responsible to track the checkpoint status of all stakers, and execute such function on behalf
of the users by using `crossCheckpointTo()`. However, users is also allowed to cross the checkpoint themselves by
calling the functoin `crossCheckpoint()`. This function will revert if the user `canCrossCheckpoint()` is false.

It is important to note, that a number of functions will revert if `canCrossCheckpoint()` returns true, until the user
crosses the checkpoint. This is to avoid undesired states of rewards not being allocated properly.

### Claims

- The method `claim()` allows a user to claim the vested rewards.
- This function should be independent of any other contract state: no funds for staking rewards, checkpoints crossed or
  not crossed, etc. Once tokens are vested, they should be claimables no matter what happens.

### Withdrawals

- The method `withdraw()` allows a user to get unstaked tokens back to his wallet, once the `unstakingReleaseTime` has
  passed.
- This function should be independent of any other contract state: no funds for staking rewards, checkpoints crossed or
  not crossed, etc. Unstaked tokens that have been released should be withdrawable no matter what happens.

### Relocking

- The method `relock()` allows a user to relock
- Relock is only allowed if `canCrossCheckpoint()` returns `false`. This avoids a user postponing the checkpoint without
  having converted their unvested rewards into vested.

### Tiers and thresholds

The biggest challenge is that the tier thresholds must be kept constant in dollar value. The team decided not to rely
on oracles, to reduce the risks related to oracle manipulation. Instead, in the contract the tier thresholds are set in
VINCI value, which means that the contract operators will be responsible for updating the thresholds regularly,
to keep them constant in dollar value.

The frequncy at which these will be tracked will depend on network congestion and price fluctuations.

### View functions: earned staking rewards

**IMPORTANT**: the ouput of the view functions is only reliable if the checkpoints are up-to-date (if
canCrossCheckpoint() = false). Otherwise, the contract cannot guarantee that the output will be reliable

#### Earned base APR rewards

The challenge here is that the staking amount can change during the staking period (the user can stake/unstake).
Keeping track of the rewards generated by each staked amount and duration is costly an expensive. Luckly we can use the
following trick:

- The rewards are only vested at the end of the staking period.
- The rewards allocated to a user, (vested in the next checkpoint) are updated with every stake/unstake. Which means
  that they are always up to date, as long as a checkpoint hasn't been reached.
- At any given time the next checkpoint timestamp is known as well as the staked amount, which means that it is possible
  to calculate the rewards that will be earned from the time of calculating until the next checkpoint. These are the
  rewards that are reserved but not earned yet.
- The rewards earned at time _t_ are the rewards allocated to the user at the end of the period, minus the rewards that
  have not been earned yet.

Note:

- If `canCrossCheckpoint()` returns `true`, the output from this function can't be trusted. The frontend should take
  care of this.

## Contract Invariants

- tokens entering contract - tokens leaving contract = contract balance

## Contract operation

- Keeping the staking-rewards fund filled with enough Vinci to allocate rewards to stakers
- Updating the tier thresholds regularly (in VINCI value) to keep them contant at dollar value

## Known vulnerabilities / centralization issues

- The contract operators can manipulate the tier thresholds to their benefit and therefore:
    - Set the thresholds artificially low before staking and therefore get a very high tier status unfairly. This
      vulnerability has very low risk with respect to the staking rewards and staking balances, as the tier system has
      no influence in any of the staking logic. It is only a tier tracker, but all benefits from offchain


- **IMPORTANT:** if the contract enters a state in which `canCrossCheckpoint()` returns true, but `crossCheckpoint()`
  reverts,
  the tokens will be locked in the contract forever. The auditors should put special focus on this point.
