// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPoolERC20 {
    /**
     * @notice An executed shares transfer from `sender` to `recipient`.
     *
     * @dev emitted in pair with an ERC20-defined `Transfer` event.
     */
    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 sharesValue
    );

    function transferShares(
        address _recipient,
        uint256 _sharesAmount
    ) external returns (uint256);
}
