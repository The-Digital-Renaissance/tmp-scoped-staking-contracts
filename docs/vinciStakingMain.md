# VINCI Staking contract

## High level overview

Vinci staking is a staking pool contract that allows users to stake their Vinci tokens and earn rewards in Vinci tokens
exclusively. A system of checkpoints, unstaking penalizations and Superstaker status is used to retain stakers for
longer periods of time. A system of tiers is used to incentive users to stake as much as possible, although the rewards
of having high tiers are not implemented in the contract, as it will be handled mostly offchain, and then airdropped
to the stakers in the contract.

## Contract Requirements

- [Staking Contract requirements](./vinciStakingRequirements.md)

## Implementation overview

- [Staking Contract implementation overview](./vinciStakingImplementation.md)

## Contract opertions

### Contract deployment
- Vinci token needs to be deployed 
- Deployment of VinciStakingV1 with contract arguments:
  - Vinci token address
  - Ttier thresholds
- Roles:
  - Grant the `CONTRACT_FUNDER_ROLE` to the Vinci safes that will have Vinci tokens dedicated to fund staking rewards
  - Grant the `CONTRACT_OPERATOR_ROLE` to the address that will operate the following functions:
    - updating tier thresholds 
    - crossing checkpoints for users
    - airdropping extra rewards by using `batchAirdrop()` (needs vinci funds)
    - staking on behalf of pre-stakers by using `batchStakeTo()` (needs vinci funds)
  - Renounce `DEFAULT_ADMIN_ROLE` by deployer, as it could grant roles at will

