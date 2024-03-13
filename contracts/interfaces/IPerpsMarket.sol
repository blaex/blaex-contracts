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
        uint256 id;
        address account;
        uint256 market;
        address collateralToken;
        uint256 sizeInUsd;
        uint256 sizeInToken;
        uint256 collateralInUsd;
        int256 realisedPnl;
        int256 paidFunding;
        int256 latestInteractionFunding;
        uint256 paidFees;
        bool isLong;
        bool isClose;
        bool isLiquidated;
    }

    struct Order {
        uint256 id;
        address account;
        uint256 market;
        address collateralToken;
        OrderType orderType;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionPrice;
        uint256 protocolFees;
        uint256 keeperFees;
        uint256 submissionTime;
        uint256 executionTime;
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
        uint256 market;
        address collateralToken;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        OrderType orderType;
        bool isLong;
    }

    // struct ExecuteOrderParams {
    //     uint256 id;
    //     uint256 minOracleBlockNumbers;
    //     uint256 maxOracleBlockNumbers;
    //     address keeper;
    // }

    function createOrder(CreateOrderParams calldata params) external;

    // function cancelOrder(uint256 id) external;

    // function executeOrder(uint256 id) external;

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
        uint256 executionPrice,
        uint256 protocolFees,
        uint256 keeperFees
    );

    event OrderCanceled(uint256 orderId, uint256 executeTime);

    event OrderExecuted(
        uint256 orderId,
        uint256 executePrice,
        uint256 executeTime
    );

    event PositionModified(
        uint256 positionId,
        address account,
        uint256 market,
        address collateralToken,
        uint256 sizeInUsd,
        uint256 sizeInToken,
        uint256 collateralInUsd,
        int256 realisedPnl,
        int256 paidFunding,
        int256 latestInteractionFunding,
        uint256 paidFees,
        bool isLong,
        bool isClose
    );
}
