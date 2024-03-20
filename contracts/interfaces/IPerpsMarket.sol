// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IPerpsMarket {
    enum OrderType {
        Liquidation,
        Market,
        Limit,
        Stop
    }

    struct Market {
        uint256 id;
        string symbol;
        bytes32 priceFeedId;
        uint256 maxSkew;
        bool enable;
        uint256 size;
        int256 skew;
        int256 lastFundingRate;
        int256 lastFundingValue;
        uint256 lastFundingTime;
    }

    struct Position {
        uint256 id;
        address account;
        uint256 market;
        bool isLong;
        uint256 sizeInUsd;
        uint256 sizeInToken;
        uint256 collateralInUsd;
        uint256 sl;
        uint256 tp;
        uint256 paidFees;
        int256 realisedPnl;
        int256 paidFunding;
        int256 latestInteractionFunding;
        bool isClose;
        bool isLiquidated;
    }

    struct Order {
        address account;
        uint256 market;
        bool isLong;
        bool isIncrease;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionPrice;
        uint256 orderFees;
        uint256 executionFees;
        uint256 submissionTime;
        bool isExecuted;
        bool isCanceled;
    }

    struct CreateMarketParams {
        uint256 id;
        string symbol;
        bytes32 priceFeedId;
        uint256 maxSkew;
    }

    struct CreateOrderParams {
        uint256 market;
        uint256 sizeDeltaUsd;
        uint256 collateralDeltaUsd;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        bool isLong;
        bool isIncrease;
    }

    function createMarket(CreateMarketParams calldata params) external;

    function updateMarketSettings(
        uint256 _id,
        uint256 _maxSkew,
        bool _enable
    ) external;

    function createOrder(CreateOrderParams calldata params) external;

    function cancelOrder(uint256 id) external;

    function executeOrder(
        uint256 _id,
        bytes[] calldata _priceUpdateData
    ) external payable;

    function executeSltp(
        uint256 _positionId,
        bytes[] calldata _priceUpdateData
    ) external payable;

    function indexPrice(
        uint256 marketId
    ) external view returns (uint256 currentPrice);

    function getPosition(uint256 id) external view returns (Position memory);

    function getOrder(uint256 id) external view returns (Order memory);

    function getPendingOrders(
        address account
    ) external view returns (Order[] memory);

    function getOpenPositions(
        address account
    ) external view returns (Position[] memory);

    function setKeeperFee(uint256 _keeperFee) external;

    function setOrderFee(uint256 _orderFee) external;

    function setMinCollateral(uint256 _minCollateral) external;

    function setMaxCollateral(uint256 _minCollateral) external;

    function setMaxLeverage(uint256 _maxLeverage) external;

    event MarketCreated(
        uint256 marketId,
        string symbol,
        bytes32 priceFeedId,
        uint256 maxSkew,
        bool enable
    );

    event MarketUpdated(uint256 marketId, uint256 maxSkew, bool enable);

    event KeeperFeeChanged(uint256 keeperFee);

    event OrderFeeChanged(uint256 orderFee);

    event MinCollateralChanged(uint256 minCollateral);

    event MaxCollateralChanged(uint256 maxCollateral);

    event MaxLeverageChanged(uint256 maxLeverage);

    event OrderSubmitted(
        uint256 orderId,
        address account,
        uint256 market,
        bool isLong,
        uint256 collateralDeltaUsd,
        uint256 sizeDeltaUsd,
        uint256 triggerPrice,
        uint256 acceptablePrice,
        uint256 orderFees,
        uint256 executionFees
    );

    event OrderCanceled(uint256 orderId, bytes32 reason);

    event OrderExecuted(
        uint256 orderId,
        uint256 executionPrice,
        uint256 executionTime
    );

    event SltpUpdated(uint256 positionId, uint256 sl, uint256 tp);

    event SltpExecuted(
        uint256 positionId,
        uint256 executionPrice,
        uint256 executionTime
    );

    event PositionModified(
        uint256 positionId,
        address account,
        uint256 market,
        bool isLong,
        uint256 sizeInUsd,
        uint256 sizeInToken,
        uint256 collateralInUsd,
        int256 realisedPnl,
        int256 paidFunding,
        int256 latestInteractionFunding,
        uint256 paidFees,
        bool isClose,
        bool isLiquidated
    );

    event PositionLiquidated(
        uint256 positionId,
        uint256 returnedCollateral,
        uint256 orderFees,
        uint256 executionFees
    );
}
