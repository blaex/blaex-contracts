// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBLI is IERC20 {
    struct DailyStatistic {
        uint256 timestamp;
        int256 pnl;
        uint256 realYield;
        uint256 nativeYield;
    }

    event Deposit(address sender, uint256 value);

    event Withdraw(address receiver, uint256 value);

    event ChargeFee(address sender, address receiver, uint256 value);

    event UpdatedFee(uint256 fee);

    event UpdatedFeeReceiver(address feeReceiver);

    event DailyStatisticUpdated(
        uint256 timestamp,
        int256 pnl,
        uint256 realYield,
        uint256 nativeYield,
        uint256 totalShares,
        uint256 totalPooledToken
    );

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getFee() external returns (uint256);

    function getFactor() external returns (uint256);
}
