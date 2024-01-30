// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IUSDB.sol";

contract USDB is ERC20, IUSDB {
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    constructor() ERC20("USDB", "USDB") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
