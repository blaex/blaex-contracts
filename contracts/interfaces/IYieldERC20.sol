// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IYieldERC20 {
    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);

    function sharesOf(address _account) external view returns (uint256);
}
