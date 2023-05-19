# Vinci LP Staking contract

A staking contract that allows user to stake their LP tokens in echange for Vinci rewards.
Only once the liquidity pool has been created in a certain DEX, the address of the LP token contract will be known.
The LP staking contract will be deployed only then.

## Requirements

- Any wallet is allowed to stake LP tokens
- When staking, a user must decide in advance for how long he wants to stake.
- Once commiting to a period, the tokens cannot be retrieved until that period finishes
- Only 3 periods are allowed: 4 month, 8 months and 12 months. The rewards for each length are different.

### Rewards

There are 2 types of rewards. Both are paid in Vinci tokens:

- An instant payout the staker gets at the moment of staking. The size of the payout depends on the size of the
  stake, and also on the number of months staked
- On a weekly basis, a fixed amount of Vinci tokens are distributed proportionally among all stakers. However,
  the accessibility of these rewards depend on the number of months locked:
    - A share of those rewards are available immediately after they are distributed by the contract owner
    - The remaining are only unlocked at the end of the staking period
    - The weekly amount to be distributed can be changed by the contract owners. 
- Depending on the number of months, the percentage of rewards that are available immediately or at the end, is
  different
- If a weekly distribution is missed, the contract must keep track of the missing payouts and catch up at a later stage.
- The funds for instant payouts is limited, and once emptied, users can no longer expect instant payouts.

| Months | Instant payout | Available weekly | Available at the end |
|--------|----------------|------------------|----------------------|
| 12     | 5%             | 100%             | 0%                   |
| 8      | 1.5%           | 50%              | 50%                  |
| 4      | 0.5%           | 0%               | 100%                 |

## Implementation overview

- The stakes of each user are kept in a array of structs called `Stake`, which contains information about when and how
  long they will be staked, the amount, if they have been withdrawn already and some information related to the claimed
  rewards.
- The rewards are tracked at a `Stake` level, not at a user level. A user must withdraw or claim rewards of each stake
  independently.
- This granularity allows an infinite amount of stakes per user, without the risk of gas-limitations, as iterations over
  the array of stakes is not needed (except in view functions).

### APR distribution

Each week, the contract operator can distribute a fixed amount of tokens among all stakers.
The amount of weely tokens is fixed by contract.

To minimize gas costs of the distribution of the weekly APR, the approach is to
track the total amount of LP tokens staked, and the amount of Vinci tokens corresponding to each LP token.
In this way, when the APR distribution happens, only one variable needs to be updated: the number of Vinci corresponding
to each LP token increases.
In that way, the corresponding Vinci rewards allocated to each staker increments automatically.

These rewards are modified with a multiplier that depends on the lenght of the staking period,
that controlls wether those rewards are available immediately or at the end of the period.

### Instant payout

The instant payouts however, requires to calculate the price ratio between the LP tokens and Vinci tokens, because the
user stakes LP tokens, and the instant payout is done on Vinci tokens.

To avoid relying on oracles, the team decided to be the oracle themselves, and set the price manually on a weekly basis
or with certain undetermined frequency. This gives of course a tremendous power to the contract operator to change the
price ratio at will and get an insane amount of rewards.

### Contract funding

- There are two pools that requrire funding:
    - Funding for the instant payouts
    - Funding for the APR distribution (staking rewards)
- Any wallet is allowed to fund any of those two pools with Vinci

### Contract Invariants

- The balance of LP tokens in the contract must match the sum of the LP tokens staked by all users
- The balance of Vinci tokens in the contract must match the sum of all vinci rewards allocated to all stakes, plus the
  fund pools for staking rewards and instant payouts

## Contract operation

The following operational tasks are required once the contract is deployed:

- funding the contract with Vinci for instant payouts
- funding the contract with Vinci for APR distribution
- weekly distribution of rewards
- weekly setting of the price ratio between LP tokens and Vinci tokens
- every 4 months, update the weekly amount to be distributed

## Known vulnerabilities / centralization issues:

- contract operator can manipulate de price of LP tokens in vinci and therefore:
    - artificially inflate it before staking and get a disproportionate payout
    - reduce the payout artificially so that instant payouts are ridiculously low 