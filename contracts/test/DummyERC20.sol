// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * Contract used for unit tests
 */
contract DummyERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(uint256 amount) public {
        _mint(_msgSender(), amount);
    }

    function mintTo(uint256 amount, address to) public {
        _mint(to, amount);
    }
}
