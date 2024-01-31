// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPerpsVaultCallback {
    function payCallback(uint256 amount) external;
}
