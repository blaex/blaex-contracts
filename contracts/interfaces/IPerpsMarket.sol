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
        uint256 id;
        string symbol;
        uint256 size;
        int256 skew;
        int256 lastFundingRate;
        int256 lastFundingValue;
        uint256 lastFundingTime;
        bytes32 priceFeedId;
        bool enable;
    }

    struct Position {
        address account;
        uint256 market;
        address collateralToken;
        uint256 id;
        uint256 sizeInUsd;
        uint256 sizeInToken;
        uint256 collateralInUsd;
        int256 realisedPnl;
        int256 paidFunding;
        int256 latestInteractionFunding;
        bool isLong;
        bool isClose;
    }

    struct Order {
        address account;
        uint256 market;
        address collateralToken;
        uint256 id;
        OrderType orderType;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 keeperFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
        uint256 updatedAtBlock;
        bool isLong;
        bool isFilled;
        bool isCanceled;
    }

    struct CreateMarketParams {
        uint256 id;
        string symbol;
        bytes32 priceFeedId;
    }

    struct CreateOrderParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        uint256 market;
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

    function getOrder(uint256 id) external view returns (Order memory);

    function getPosition(uint256 id) external view returns (Position memory);

    function getOpenOrders(
        address account
    ) external view returns (Order[] memory);

    function getOpenPositions(
        address account
    ) external view returns (Position[] memory);

    function setKeeperFee(uint256 _keeperFee) external;

    function setProtocolFee(uint256 _protocolFee) external;

    function setEnableExchange(bool _enableExchange) external;

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

    event PositionModified(
        uint256 positionId,
        address indexToken,
        address sizeInUsd,
        address sizeDeltaInUsd,
        address collateralInUsd,
        address collateralDeltaInUsd,
        bool isLong
    );
}
