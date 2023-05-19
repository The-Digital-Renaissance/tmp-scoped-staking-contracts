pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    // This contract represents any different ERC20 than Vinci
    constructor() ERC20("Mock ERC20", "MOCKERC20") {
        _mint(address(this), 5000 * 10 ** 18);
    }
}
