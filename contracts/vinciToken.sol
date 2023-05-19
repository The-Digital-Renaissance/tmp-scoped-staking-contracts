// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

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

/// @title Vinci ERC20 Token
contract Vinci is ERC20, AccessControl {
    // @dev Struct to hold how many tokens are due to an address at the specified time
    bytes32 public constant CONTRACT_OPERATOR_ROLE = keccak256("CONTRACT_OPERATOR_ROLE");

    // to be able to pack the Timelocks in a gas efficient way, we took some assumptions.
    // uint64.max is equivalent to year 2550, so we are far from reaching that
    // amount is very far away from reaching uint128.max
    struct TimeLock {
        uint160 amount;
        uint64 releaseTime;
        bool claimed;
    }

    uint256 public freeSupply;
    mapping(address => TimeLock[]) public timeLocks;

    uint256 public constant MAX_VESTINGS_PER_ADDRESS = 100;

    constructor() ERC20("Vinci", "VINCI") {
        _mint(address(this), 200 * 500 * 10 ** 6 * 10 ** 18);
        freeSupply = totalSupply();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(CONTRACT_OPERATOR_ROLE, msg.sender);
    }

    error InvalidAddress();
    error InvalidVestingSchedule();
    error ExceedsMaxVeestingsPerWallet();

    event TokensLocked(address indexed beneficiary, uint256 amount, uint256 releaseTime);
    event TokensClaimed(address indexed beneficiary, uint256 amount, uint256 releaseTime);

    // @dev This withdraws VINCI tokens that have not been allocated to vestings (but have been minted)
    function withdraw(address recipient, uint256 amount) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        require(amount <= freeSupply, "amount exceeds free supply");
        _transfer(address(this), recipient, amount);
        freeSupply -= amount;
    }

    function burn(uint256 amount) external {
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
                // the timelock.amount is uint160 so it is safe to unchecked-add it to total
                unchecked {
                    total += amount;
                }
                timeLock.claimed = true;
                emit TokensClaimed(user, amount, timeLock.releaseTime);
            }
        }
        _transfer(address(this), user, total);
    }

    // set vestings of individual users
    function setVestingSchedule(address user, TimeLock[] calldata vestings) external onlyRole(CONTRACT_OPERATOR_ROLE) {
        if (user == address(0)) revert InvalidAddress();
        if (timeLocks[user].length + vestings.length > MAX_VESTINGS_PER_ADDRESS) revert ExceedsMaxVeestingsPerWallet();

        uint256 total;
        uint256 numberOfVestings = vestings.length;
        for (uint256 i = 0; i < numberOfVestings; i++) {
            if ((vestings[i].amount == 0) || (vestings[i].claimed == true)) revert InvalidVestingSchedule();

            timeLocks[user].push(vestings[i]);
            emit TokensLocked(user, vestings[i].amount, vestings[i].releaseTime);
            total += vestings[i].amount;
        }
        // only change storage variable once
        // this will revert in case of overflow/underflow
        freeSupply -= total;
    }

    // view functions

    function getNumberOfTimelocks(address user) external view returns (uint256) {
        return timeLocks[user].length;
    }

    function readTimelock(address user, uint256 index) external view returns (TimeLock memory) {
        return timeLocks[user][index];
    }

    // returns the sum of all expired timeLocks
    function getTotalVestedTokens(address user) external view returns (uint256) {
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
    function getTotalUnvestedTokens(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256 length = timeLocks[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (timeLocks[user][i].releaseTime > block.timestamp) {
                total += timeLocks[user][i].amount;
            }
        }
        return total;
    }

    // gets the sum of all claimed timeLocks
    function getTotalClaimedTokens(address user) external view returns (uint256) {
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
