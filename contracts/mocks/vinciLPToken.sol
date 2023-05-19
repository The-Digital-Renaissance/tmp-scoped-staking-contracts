// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VinciMockLPToken is ERC20("LPVINCI", "LPVINCI") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
