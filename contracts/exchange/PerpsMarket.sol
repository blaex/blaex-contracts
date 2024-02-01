// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket {
    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);
    IPerpsVault perpsVault;
    bool enableExchange;
    mapping(address => Market) market;
    uint256 protocolFee = 500;
    uint256 constant FACTOR = 10000;

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

    modifier onlyPerpsVault() {
        require(
            address(perpsVault) == msg.sender,
            "PerpsMarket: Only PerpsVault"
        );
        _;
    }

    function depositCollateralCallback(
        uint256 _amount
    ) external onlyPerpsVault {
        USDB.transfer(address(perpsVault), _amount);
    }

    function createOrder(
        CreateOrderParams calldata params
    ) external whenEnableExchange returns (uint256) {
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

    function cancelOrder(uint256 id) external whenEnableExchange {
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
            abi.encode(order.account, order.market, order.isLong)
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

        USDB.transferFrom(
            order.account,
            address(this),
            order.collateralDeltaUsd
        );
        perpsVault.depositCollateral(order.account, order.collateralDeltaUsd);

        bool isNew = position.sizeInUsd == 0 && !position.isClose;
        if (isNew) {
            //Addresses
            position.account = order.account;
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

        uint256 fees = (order.sizeDeltaUsd * protocolFee) / FACTOR;
        perpsVault.settleTrade(order.account, 0, fees);
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
        uint256 fees = (order.sizeDeltaUsd * protocolFee) / FACTOR;
        uint256 receivedAmount = order.collateralDeltaUsd - fees;
        if (pnl >= 0) {
            receivedAmount += _abs(pnl);
        } else {
            receivedAmount -= _abs(pnl);
        }
        perpsVault.settleTrade(order.account, pnl, fees);
        perpsVault.withdrawCollateral(order.account, receivedAmount);
        USDB.transfer(order.account, receivedAmount);
    }

    function verifyOrder(uint256 id) internal returns (Order memory) {
        require(id > 0 && id < orderId, "Invalid order id");

        Order memory order = orders[id];
        require(!order.isFilled, "Order already filled");
        require(!order.isCanceled, "Order already canceled");

        return order;
    }

    function _abs(int256 x) internal pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
    }
}
