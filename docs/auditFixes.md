# Audit Fixes

## Overview:

- H.01: fixed
- H.02: fixed
- H.03: fixed
- H.04: fixed
- H.05: fixed


- M.01: fixed
- M.02: acknowledged


- L.01: acknowledged
- L.02: disputed
- L.03: fixed
- L.04: acknowledged
- L.05: fixed
- L.06: acknowledged
- L.07: fixed


- I.01: fixed
- I.02: fixed
- I.03: fixed
- I.04: fixed
- I.05: fixed
- I.06: fixed
- I.07: acknowledged
- I.08: fixed

## High severity

### H.01:  [Fixed]

#### Super stakers will receive inflated rewards from penalty pot due to unaccounted debt.

Fixed following recommendation. The penaltyPot is buffered for stakers becoming superstakers:

    if (!_isSuperstaker(user)) {
        _bufferPenaltyPotAllocation(user, 0);
        _addToElegibleSupplyForPenaltyPot(activeStake);
    }

### H.02: [Fixed]

#### Stakers will receive twice their rewards when they cross a checkpoint after a missed period

Fixed following recommendation. The method `_postponeCheckpoint()` is now the responsible of returning the start time of
the current rewards
period of which the rewards needs to be calculated afterwards. The rewards for the missed period
and the rewards of the missed period are then calculated with the corresponding functions:

    (uint256 missedPeriod, uint256 currentPeriodStartTime, uint256 newCheckpoint) = _postponeCheckpoint(user);
        ...    
        uint256 missedRewards = _estimatePeriodRewards(activeStake, missedPeriod);
        ...
    uint256 rewards = _estimatePeriodRewards(activeStake, newCheckpoint - currentPeriodStartTime);

Perhaps the implementation of `_postponeCheckpoint()` should be revised by the auditor.

### H.03: [Fixed]

#### Penalization of penalty pot rewards can be circumvented.

Fixed following recommendation.

    individualBuffer[user] = updatedBuffer;

### H.04: [Fixed]

#### A portion of the funds for staking rewards will be locked in the LPstaking contract.

Fixed following recommendation. The `_sendStakingRewards()` no longer substracts from `fundsForStakingRewards`.

    function _sendStakingRewards(address to, uint256 amount) internal {
        // There should always be enough funds to pay the rewards, because the distributeAPR function only distributes
        // if there are funds available
        require(vinciToken.transfer(to, amount));
    }

### H.05 [Fixed]

#### Super staker rewards will be incorrectly sent to users that are not yet super stakers.

Fixed following recommendation.

    uint256 penaltyPotShare = _isSuperstaker(user) ? _redeemPenaltyPot(user, activeStake) : 0;

# Medium severity

### M.01: [Fixed]

#### Instant Vinci rewards are calculated with the wrong precision.

Fixed following recommendation.

    uint256 vinciInstantPayout = (amount * LPpriceInVinci * instantPayoutMultiplier[monthsLocked])
        / (10 ** lpToken.decimals() * BASIS_POINTS);

### M.02: [Acknowledged]

#### Weekly LP staking rewards are distributed from the wrong starting date

It is a valid observation, however, even if the launch is delayed some days, we want to that reference date to start
counting
the weeks of rewards distribution.

We do not intend to re-launch the contract.

### L.01: [Acknowledged]

#### Users can maintain a stake of just 1 wei to keep the super staker status.

The dev team is well aware of this scenario and notified the responsible
of designing the staking and superstaker mechanism. However, they decided to keep it that way under the premise:

- tiers acknoledge the size of your stake (and ignores the time-factor)
- superstaker acknowledge the length (and ignores the size-factor)

### L.02: [Disputed]

#### The Vinci token operator has control over the whole project value.

The `CONTRACT_OPERATOR_ROLE` has indeed the power to withdraw some minted Vinci tokens.
However, they can never withdraw tokens that have been allocated to vesting schedules. So neither vested or unvested
tokens
can be withdrawn by the operator.

The `withdraw()` method only allows to withdraw up to `freeSupply`.

    function withdraw(address recipient, uint256 amount) public onlyRole(CONTRACT_OPERATOR_ROLE) {
        require(amount <= freeSupply, "amount exceeds free supply");

However, the `setVestingSchedule()` method subtracts the vested amounts from the free supply when allocating
vested/unvested tokens. Therefore, the tokens allocated to vesting schedules do not for part of the `freeSupply` and
cannot be withdrawn by the operator.

    function setVestingSchedule(address user, TimeLock[] calldata vestings) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        uint256 total;
        uint256 numberOfVestings = vestings.length;
        for (uint256 i = 0; i < numberOfVestings; i++) {
            ...
            total += vestings[i].amount;
        }
        ...
        freeSupply -= total;

More over, the team uses a multi-sig gnosis safe to manage these funds.

### L.03: [Fixed]

#### Insufficient input validation for vesting parameters

Fixed following recommendation. However, the release time is not validated, because we might want
to set a list of vesting schedules of which some of them have been already released.

    if (
        (vestings[i].amount == 0) ||
        (vestings[i].claimed == true)
    ) revert InvalidVestingSchedule();

### L.04: [Acknowledged]

#### Wrong accounting for penalty pot rewards.

Acknowledged and agreed. The fix is non-trivial with the current implementation.

### L.05: [Fixed]

#### An unbounded loop may cause DoS for Vinci token vestings.

Fix: imposing a hard limit to the amount of Vestings (TimeLocks) for a given wallet.
The hard limit is checked in the `setVestingSchedule()` method before adding Timelocks to the
`timeLocks` array. Therefore, iterating over that array is now bounded.

    uint256 public constant MAX_VESTINGS_PER_ADDRESS = 100;
    ...

    function setVestingSchedule(address user, TimeLock[] calldata vestings) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        ...
        if (timeLocks[user].length + vestings.length > MAX_VESTINGS_PER_ADDRESS) revert ExceedsMaxVeestingsPerWallet();

### L.06: [Acknowledged]

#### The LP staking operator can block staking functionality.

The team is aware of the power that the contract operator has over the LP staking contract.
However, it is very estimate an upper bound to  `LPpriceInVinci` before the LP pair is created.

### L.07 [Fixed]

#### Wrong value is used for weekly rewards in sanity check

Fixed according to suggestions.

    function distributeWeeklyAPR() external {
        uint256 _buffered = bufferedDecimals;
        if (fundsForStakingRewards < WEEKLY_VINCI_REWARDS + _buffered) revert InsufficientVinciInLPStakingContract();
        ...

# Informational

### I.01 [Fixed]

#### Storage variables can be marked constant or immutable.

All fixed.

### I.02 [Fixed]

#### Missing zero address checks

Not fixed to save gas.

### I.03 [Fixed]

#### Public functions can be marked external.

All fixed.

### I.04 [Fixed]

#### Unstaking 0 amount should not be allowed.

Fixed.

### I.05 [Fixed]

#### Function incorrect as per spec.

This observation is correct. Initially, it was meant to be executable by anyone, but a last minute change
was to make it exclusive for the `CONTRACT_FUNDER_ROLE`. However the documentation was not updated.

Documentation has been updated.

### I.06 [Fixed]

#### Unsafe ERC20 operations.

VinciStakingV1 does use Safe operations for ERC20 transfers.
In fact, using safe operations is mostly necessary when the nature of the tokens is unknown. However, as here we only
operate with known tokens (LPtokens and Vinci tokens) the use of SafeERC20 is not strictly necessary.
However, for the sake of completeness, we have decided to follow the audit recommendations and also use it in the LP
staking contract.

### I.07 [Acknowledged]

#### Thresholds order is not validated.

This check is avoided on purpose to save gas. The function to set the thresholds is going to be executed quite regularly
so we want to save as much gas as possible.

### I.08 [Fixed]

#### Typographical mistakes.

Unused struct `VestingSchedule` has been removed.  