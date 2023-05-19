// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract VinciMockToken is ERC20, AccessControl {
    // @dev Struct to hold how many tokens are due to an address at the specified time
    bytes32 public constant CONTRACT_OPERATOR_ROLE = keccak256("CONTRACT_OPERATOR_ROLE");

    struct TimeLock {
        uint256 amount;
        uint128 releaseTime;
        bool claimed;
    }

    struct VestingSchedule {
        TimeLock[] timelocks;
    }

    uint256 public freeSupply;

    mapping(address => uint256) public totalClaimed;
    mapping(address => TimeLock[]) public timeLocks;

    constructor() ERC20("Vinci", "VINCI") {
        _mint(address(this), 200 * 500 * 10 ** 6 * 10 ** 18);
        freeSupply = totalSupply();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(CONTRACT_OPERATOR_ROLE, msg.sender);
    }

    event TokensLocked(address indexed beneficiary, uint256 amount, uint256 releaseTime);

    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 releaseTime);

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function withdraw(address recipient, uint256 amount) public onlyRole(CONTRACT_OPERATOR_ROLE) {
        require(amount <= freeSupply, "amount exceeds free supply");
        _transfer(address(this), recipient, amount);
        freeSupply -= amount;
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // Claims all unlocked tokens for the given user
    function claim() external {
        address user = msg.sender;
        TimeLock[] storage userTimeLocks = timeLocks[user];
        uint256 total = 0;

        // this saves gas
        uint256 length = userTimeLocks.length;

        for (uint256 i = 0; i < length; i++) {
            TimeLock storage timeLock = userTimeLocks[i];

            if (timeLock.releaseTime <= block.timestamp && !timeLock.claimed) {
                uint256 amount = timeLock.amount;
                total += amount;
                timeLock.claimed = true;
                emit TokensClaimed(user, amount, timeLock.releaseTime);
            }
        }

        totalClaimed[user] += total;
        _transfer(address(this), user, total);
    }

    // set vestings of individual users
    function setVestingSchedule(address user, TimeLock[] calldata vestings) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        uint256 total;
        uint256 numberOfVestings = vestings.length;
        for (uint256 i = 0; i < numberOfVestings; i++) {
            timeLocks[user].push(vestings[i]);
            emit TokensLocked(user, vestings[i].amount, vestings[i].releaseTime);
            total += vestings[i].amount;
        }
        // only change storage variable once
        freeSupply -= total;
    }

    // view functions

    function getNumberOfTimelocks(address user) public view returns (uint256) {
        return timeLocks[user].length;
    }

    function readTimelock(address user, uint256 index) public view returns (TimeLock memory) {
        return timeLocks[user][index];
    }

    // returns the sum of all expired timeLocks
    function getTotalVestedTokens(address user) public view returns (uint256) {
        uint256 total = 0;
        uint256 length = timeLocks[user].length;
        for (uint256 i = 0; i < length; i++) {
            if ((timeLocks[user][i].releaseTime <= block.timestamp)) {
                total += timeLocks[user][i].amount;
            }
        }
        return total;
    }

    // gets the sum of all non-expired timeLocks
    function getTotalUnVestedTokens(address user) public view returns (uint256) {
        uint256 total = 0;
        uint256 length = timeLocks[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (timeLocks[user][i].releaseTime > block.timestamp) {
                total += timeLocks[user][i].amount;
            }
        }
        return total;
    }

    // gets the sum of all non-expired timeLocks
    function getTotalClaimedTokens(address user) public view returns (uint256) {
        uint256 total = 0;
        uint256 length = timeLocks[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (timeLocks[user][i].claimed) {
                total += timeLocks[user][i].amount;
            }
        }
        return total;
    }
}
