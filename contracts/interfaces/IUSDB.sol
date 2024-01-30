// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDB is IERC20 {
    function mint(address account, uint256 amount) external;
}
