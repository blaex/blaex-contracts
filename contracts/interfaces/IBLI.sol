// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBLI is IERC20 {
    struct DailyStatistic {
        uint256 timestamp;
        uint256 depositAmount;
        uint256 withdrawAmount;
        uint256 feeAmount;
        uint256 pnlAmount;
        uint256 yieldAmount;
    }

    event Deposit(address sender, uint256 value);

    event Withdraw(address receiver, uint256 value);

    event UpdatedFee(uint256 fee);

    event UpdatedFeeReceiver(address feeReceiver);

    event DailyStatisticUpdated(
        uint256 timestamp,
        uint256 depositAmount,
        uint256 withdrawAmount,
        uint256 feeAmount,
        uint256 pnlAmount,
        uint256 yieldAmount,
        uint256 totalShares,
        uint256 totalPooledToken
    );

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getFee() external returns (uint256);

    function getFactor() external returns (uint256);
}
