// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPerpsMarketIntegrated {
    function depositCollateralCallback(uint256 amount) external;
}
