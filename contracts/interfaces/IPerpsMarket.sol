// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPerpsMarket {
    enum OrderType {
        MarketIncrease,
        LimitIncrease,
        MarketDecrease,
        LimitDecrease,
        Liquidation
    }

    struct Market {
        address token;
        bool enable;
    }

    struct Position {
        address account;
        address market;
        address collateralToken;
        uint256 id;
        uint256 sizeInUsd;
        uint256 sizeInToken;
        uint256 collateralInUsd;
        int256 realisedPnl;
        bool isLong;
        bool isClose;
    }

    struct Order {
        address account;
        address receiver;
        address market;
        address collateralToken;
        uint256 id;
        OrderType orderType;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
        uint256 updatedAtBlock;
        bool isLong;
        bool isFilled;
        bool isCanceled;
    }

    struct CreateOrderParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address collateralToken;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
        OrderType orderType;
        bool isLong;
    }

    struct ExecuteOrderParams {
        uint256 id;
        uint256 minOracleBlockNumbers;
        uint256 maxOracleBlockNumbers;
        address keeper;
    }

    function createOrder(CreateOrderParams calldata params) external payable;

    function cancelOrder(uint256 id) external;

    function executeOrder(
        uint256 id,
        ExecuteOrderParams memory params
    ) external;

    event SubmittedOrder(
        uint256 orderId,
        OrderType orderType,
        bool isLong,
        address account,
        address market,
        address collateralToken,
        uint256 collateralDeltaUsd,
        uint256 sizeDeltaUsd,
        uint256 triggerPrice,
        uint256 acceptablePrice,
        uint256 executionFee
    );

    event CanceledOrder(uint256 orderId);

    event ExecuteOrder(
        uint256 orderId,
        uint256 executePrice,
        uint256 executeTime
    );

    event PositionModify(
        uint256 positionId,
        address indexToken,
        address sizeInUsdl,
        address sizeDeltaInUsd,
        address collateralInUsd,
        address collateralDeltaInUsd,
        bool isLong,
    );
}
