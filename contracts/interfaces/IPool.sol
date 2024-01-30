// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPool {
    /**
     * @notice An executed `burnShares` request
     *
     * @dev Reports simultaneously burnt shares amount
     * and corresponding stToken amount.
     * The stToken amount is calculated twice: before and after the burning incurred rebase.
     *
     * @param account holder of the burnt shares
     * @param preRebaseTokenAmount amount of stToken the burnt shares corresponded to before the burn
     * @param postRebaseTokenAmount amount of stToken the burnt shares corresponded to after the burn
     * @param sharesAmount amount of burnt shares
     */
    event SharesBurnt(
        address indexed account,
        uint256 preRebaseTokenAmount,
        uint256 postRebaseTokenAmount,
        uint256 sharesAmount
    );

    function sharesOf(address _account) external view returns (uint256);
}
