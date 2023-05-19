# Vinci Staking contracts

### Disclaimer

Vinci staking does not aim to be a fully decentralized platform, and accepts that some functions in the contract are not
fully decentralized. The main goal of the contract is to provide a staking interface for users to show their
commitment to the Vinci project and earn rewards in Vinci tokens. Nonetheless, the users are always in custody of
the tokens they stake, and of the rewards they earn, as soon as they unlock them (by crossing checkpoints).

Under no circumstances the contract owners will have the custody of the tokens or the power to move them.

However, the correct distribution of rewards is subject to the contract being funded with enough VINCI tokens.
If the contract runs out of staking rewards funds, the contract cannot promise to distribute rewards anymore.
This event is unlikely as long as the company keeps working. In the case that the company goes bankrupt, the
token value itself will probably go close to cero, in which the staking rewards are the least of problems for the
investors.


## Documentation

- [Main Documentation](./docs/README.md)
- [Frontend integration docs](./docs/frontendIntegration.md)

## Audit

### Audit scope:

- [`contracts/vinciToken.sol`](contracts/vinciToken.sol)
- [`contracts/vinciStaking.sol`](contracts/vinciStaking.sol)
- [`contracts/vinciLPStaking.sol`](contracts/vinciLPStaking.sol)
- [`contracts/inheritables/checkpoints.sol`](contracts/inheritables/checkpoints.sol)
- [`contracts/inheritables/penaltyPot.sol`](contracts/inheritables/penaltyPot.sol)
- [`contracts/inheritables/tiers.sol`](contracts/inheritables/tiers.sol)

### Auditor:
- Name: gogo the auditor
- https://twitter.com/gogotheauditor


### Audit report, and fixes:

- [Gogo - Solo security review](./docs/Vinci-Solo-Security-Review.pdf)
- [Audit fixes](./docs/auditFixes.md)