# Vinci ERC20 Token

An ERC-20 token that loads tokenLocks for each user. The tokenLocks are used to lock tokens for users to be released
(by claiming) at specific times.

## Requirements

- The token must be ERC-20 compliant
- The total supply is minted at deployment, and no more tokens can be ever minted.
- The token must support token burns: any wallet is allowed to burn their tokens although the intended use is that the
  Vinci team does token buybacks and burns, manually. This will reduce total supply
- The token must be able to handle vesting schedules:
    - Vesting schedules are handled separately for each investor independently
    - The vesting schedules are set in the contract by the team, who keeps track of the investments offchain. (The
      investments are not handled by this contract, they were handled in the past by other contract).
    - Once the vesting period is finished, the token owners should be able to claim their tokens
- Basic read (view) functions to display information in the frontend relative to vesting schedules, vested/unvested
  amounts etc
- The contract owner can collect vinci tokens from the contract, but only tokens of the free supply that have not been
  allocated yet to any vesting schedule

## Implementation overview

- Vesting schedules are set with a struct called `TimeLock` which contains the amount of tokens to be vested and the
  timestamp when the tokens can be claimed, and if they have been claimed or not.
- A variable called `freeSupply` keeps track of the tokens from the total supply that have not been allocated to a
  vesting schedule or hasn't been withdrawn from the contract yet by the owner

### Contract Invariants

- The total supply cannot change once deployed and once all tokens are minted
- The contract balance must match the sum of the freeSupply, and the unclaimed tokens from all vesting schedules   

