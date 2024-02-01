// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket {
    bool enableExchange;
    mapping(address => Market) market;
    address feeReceiver;

    uint256 orderId = 1;
    uint256 positionId = 1;
    mapping(uint256 => Order) orders;
    mapping(uint256 => Position) positions;
    mapping(bytes32 => uint256) openingPositionFlag;

    constructor() {}

    modifier whenEnableExchange() {
        require(enableExchange, "Exchange is disabled");
        _;
    }

    function createOrder(
        CreateOrderParams calldata params
    ) external payable whenEnableExchange returns (uint256) {
        require(
            market[params.market].enable,
            "Market not available to trading"
        );
        require(params.receiver != address(0), "Invalid receiver");

        if (
            params.orderType == OrderType.MarketIncrease ||
            params.orderType == OrderType.LimitIncrease
        ) {
            //TODO: Charge Fee
        } else if (
            params.orderType == OrderType.MarketDecrease ||
            params.orderType == OrderType.LimitDecrease
        ) {
            //TODO: Charge Fee
        } else {
            revert("Order type is not supported");
        }

        Order memory order;
        //Addresses
        order.account = msg.sender;
        order.receiver = params.receiver;
        order.market = params.market;
        order.collateralToken = params.collateralToken;
        //Numbers
        order.orderType = params.orderType;
        order.sizeDeltaUsd = params.sizeDeltaUsd;
        order.collateralDeltaUsd = params.collateralDeltaUsd;
        order.triggerPrice = params.triggerPrice;
        order.acceptablePrice = params.acceptablePrice;
        order.executionFee = params.executionFee;
        order.callbackGasLimit = params.callbackGasLimit;
        order.minOutputAmount = params.minOutputAmount;
        //Flags
        order.isLong = params.isLong;
        //Put
        order.id = orderId;
        orders[order.id] = order;
        orderId += 1;

        //TODO: Emit event

        return order.id;
    }

    function cancelOrder(uint256 id) external payable whenEnableExchange {
        verifyOrder(id);
        orders[id].isCanceled = true;

        //TODO: Emit event
    }

    function executeOrder(
        uint256 id,
        ExecuteOrderParams memory params
    ) external {
        Order memory order = verifyOrder(id);
        orders[id].isFilled = true;

        //TODO: validate price and block

        bytes32 positionKey = keccak256(
            abi.encode(msg.sender, order.market, order.isLong)
        );

        if (
            order.orderType == OrderType.MarketIncrease ||
            order.orderType == OrderType.LimitIncrease
        ) {
            increasePosition(positionKey, order, 0, 0);
        } else if (
            order.orderType == OrderType.MarketDecrease ||
            order.orderType == OrderType.LimitDecrease
        ) {
            decreasePosition(positionKey, order, 0, 0);
        }

        //TODO: Emit event
    }

    function increasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice,
        uint256 executionPriceDecimal
    ) internal {
        Position memory position = positions[openingPositionFlag[positionKey]];

        bool isNew = position.sizeInUsd == 0 && !position.isClose;
        if (isNew) {
            //Addresses
            position.account = msg.sender;
            position.market = order.market;
            position.collateralToken = order.collateralToken;
            //Numbers
            position.sizeInUsd = order.sizeDeltaUsd;
            position.sizeInToken =
                (order.sizeDeltaUsd * executionPriceDecimal) /
                executionPrice;
            position.collateralInUsd = order.collateralDeltaUsd;
            //Flags
            position.isLong = order.isLong;
            //Put
            position.id = positionId;
            positions[position.id] = position;
            positionId += 1;
        } else {
            position.sizeInUsd += order.sizeDeltaUsd;
            position.sizeInToken +=
                (order.sizeDeltaUsd * executionPriceDecimal) /
                executionPrice;
            position.collateralInUsd += order.collateralDeltaUsd;
        }

        positions[openingPositionFlag[positionKey]] = position;
    }

    function decreasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice,
        uint256 executionPriceDecimal
    ) internal {
        Position memory position = positions[openingPositionFlag[positionKey]];

        uint256 decreaseSizeDeltaUsd = order.sizeDeltaUsd > position.sizeInUsd
            ? position.sizeInUsd
            : order.sizeDeltaUsd;
        uint256 decreaseSizeDeltaToken = (position.sizeInToken *
            order.sizeDeltaUsd) / position.sizeInUsd;
        uint256 decreaseCollateralDeltaUsd = order.collateralDeltaUsd >
            position.collateralInUsd ||
            decreaseSizeDeltaUsd == position.sizeInUsd
            ? position.collateralInUsd
            : order.collateralDeltaUsd;
        uint256 currentPositionSizeInUsd = (position.sizeInToken *
            executionPrice) / executionPriceDecimal;

        //PnL
        int256 totalPnl = position.isLong
            ? int256(currentPositionSizeInUsd - position.sizeInUsd)
            : int256(position.sizeInUsd - currentPositionSizeInUsd);
        int256 pnl = (totalPnl * int256(decreaseSizeDeltaToken)) /
            int256(position.sizeInToken);

        //Update value
        position.sizeInUsd -= decreaseSizeDeltaUsd;
        position.collateralInUsd -= decreaseCollateralDeltaUsd;
        position.sizeInToken -= decreaseSizeDeltaToken;
        position.realisedPnl += pnl;

        if (position.sizeInUsd == 0) {
            position.isClose = true;
        }

        positions[openingPositionFlag[positionKey]] = position;

        //TODO: transfer collateral & pnl
    }

    function verifyOrder(uint256 id) internal returns (Order memory) {
        require(id > 0 && id < orderId, "Invalid order id");

        Order memory order = orders[id];
        require(!order.isFilled, "Order already filled");
        require(!order.isCanceled, "Order already canceled");

        return order;
    }
}
