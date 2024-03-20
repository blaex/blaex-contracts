// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPerpsVault {
    event LiquidityVaultSetted(address liquidityVault);

    event OiLiqRatioSetted(uint256 oiLiqRatio);

    event PerpsMarketSetted(address perpsMarket);

    event DepositCollateral(address sender, uint256 value);

    event WithdrawCollateral(address receiver, uint256 value);

    event YieldClaimed(address receiver, uint256 yield);

    function depositCollateral(address _account, uint256 _amount) external;

    function withdrawCollateral(address _account, uint256 _amount) external;

    function withdrawAllCollateral(address _account) external;

    function settleTrade(address _account, int256 _pnl, uint256 _fees) external;
}
