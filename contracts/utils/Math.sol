// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

import {Authorization} from "../securities/Authorization.sol";
import "../interfaces/IPerpsMarket.sol";

library Math {
    function abs(int256 x) internal pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
    }

    function max(int x, int y) internal pure returns (int) {
        return x < y ? y : x;
    }

    function max(uint x, uint y) internal pure returns (uint) {
        return x < y ? y : x;
    }

    function min(int x, int y) internal pure returns (int) {
        return x < y ? x : y;
    }

    function min(uint x, uint y) internal pure returns (uint) {
        return x < y ? x : y;
    }
}
