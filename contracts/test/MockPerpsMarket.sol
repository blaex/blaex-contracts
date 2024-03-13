// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

contract MockPerpsMarket {
    IERC20 public constant USDB =
        IERC20(0x4300000000000000000000000000000000000003);
    // IERC20(0x4200000000000000000000000000000000000022);

    IPerpsVault perpsVault;

    modifier onlyPerpsVault() {
        require(
            address(perpsVault) == msg.sender,
            "PerpsMarket: Only PerpsVault"
        );
        _;
    }

    enum OrderType {
        MarketIncrease,
        LimitIncrease,
        MarketDecrease,
        LimitDecrease,
        Liquidation
    }

    event OrderSubmitted(
        uint256 orderId,
        OrderType orderType,
        bool isLong,
        address account,
        uint256 market,
        address collateralToken,
        uint256 collateralDeltaUsd,
        uint256 sizeDeltaUsd,
        uint256 triggerPrice,
        uint256 acceptablePrice,
        uint256 keeperFee
    );

    event OrderCanceled(uint256 orderId);

    event OrderExecuted(
        uint256 orderId,
        uint256 executePrice,
        uint256 executeTime
    );

    constructor(address _perpsVault) {
        perpsVault = IPerpsVault(_perpsVault);
    }

    function emitCreateOrder(
        uint256 orderId,
        OrderType orderType,
        bool isLong,
        address account,
        uint256 market,
        address collateralToken,
        uint256 collateralDeltaUsd,
        uint256 sizeDeltaUsd,
        uint256 triggerPrice,
        uint256 acceptablePrice,
        uint256 keeperFee
    ) external {
        emit OrderSubmitted(
            orderId,
            orderType,
            isLong,
            account,
            market,
            collateralToken,
            collateralDeltaUsd,
            sizeDeltaUsd,
            triggerPrice,
            acceptablePrice,
            keeperFee
        );
    }

    function emitExecuteOrder(
        uint256 orderId,
        uint256 executePrice,
        uint256 executeTime
    ) external {
        emit OrderExecuted(orderId, executePrice, executeTime);
    }

    function emitCancelOrder(uint256 orderId) external {
        emit OrderCanceled(orderId);
    }

    function depositCollateralCallback(
        uint256 _amount
    ) external onlyPerpsVault {
        USDB.transfer(address(perpsVault), _amount);
    }

    function depositCollateral(address _account, uint256 _amount) external {
        USDB.transferFrom(msg.sender, address(this), _amount);
        perpsVault.depositCollateral(_account, _amount);
    }

    function withdrawCollateral(address _account, uint256 _amount) external {
        perpsVault.withdrawCollateral(_account, _amount);
        USDB.transfer(_account, _amount);
    }

    function withdrawAllCollateral(address _account) external {
        perpsVault.withdrawAllCollateral(_account);
    }

    function settleTrade(
        address _account,
        int256 _pnl,
        uint256 _fees
    ) external {
        perpsVault.settleTrade(_account, _pnl, _fees);
    }
}
