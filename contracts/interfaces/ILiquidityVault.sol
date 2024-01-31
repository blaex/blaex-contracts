// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILiquidityVault {
    struct DailyStatistic {
        uint256 timestamp;
        int256 pnl;
        uint256 yield;
    }

    event Deposit(address sender, uint256 value);

    event Withdraw(address receiver, uint256 value);

    event FeeCharged(address sender, address receiver, uint256 value);

    event TradeSettled(int256 pnl, uint256 fees);

    event FeeUpdated(uint256 fee);

    event FeeReceiverUpdated(address feeReceiver);

    event PerpsVaultSetted(address perpsVault);

    event DailyStatisticUpdated(
        uint256 timestamp,
        int256 pnl,
        uint256 yield,
        uint256 totalShares,
        uint256 totalPooledToken
    );

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function settleTrade(int256 _pnl, uint256 _fees) external;

    function getFee() external returns (uint256);

    function getFactor() external returns (uint256);
}
