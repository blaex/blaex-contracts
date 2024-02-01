// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";
import {Authorization} from "../securities/Authorization.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket, Authorization {
    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);
    IPerpsVault perpsVault;
    bool enableExchange;
    mapping(uint256 => Market) markets;
    uint256 protocolFee = 500;
    uint256 constant FACTOR = 10000;

    address feeReceiver;

    uint256 orderId = 1;
    uint256 positionId = 1;
    mapping(uint256 => Order) orders;
    mapping(uint256 => Position) positions;
    mapping(bytes32 => uint256) openingPositionFlag;

    constructor(address _owner) {
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
    }

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

    function createMarket(
        CreateMarketParams calldata params
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        require(params.id != 0, "Require id");
        Market storage market = markets[params.id];
        require(market.id == 0, "Market is exist");
        market.id = params.id;
        market.symbol = params.symbol;
        market.enable = true;
    }

    function createOrder(
        CreateOrderParams calldata params
    ) external payable whenEnableExchange {
        require(
            markets[params.market].enable,
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

        emit OrderSubmitted(
            order.id,
            order.orderType,
            order.isLong,
            order.account,
            order.market,
            order.collateralToken,
            order.collateralDeltaUsd,
            order.sizeDeltaUsd,
            order.triggerPrice,
            order.acceptablePrice,
            order.executionFee
        );
    }

    function cancelOrder(uint256 id) external whenEnableExchange {
        Order memory order = verifyOrder(id);
        require(
            order.account == msg.sender,
            "Unauthorize to access this order"
        );

        orders[id].isCanceled = true;
        emit OrderCanceled(id);
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

        Position memory position;
        if (
            order.orderType == OrderType.MarketIncrease ||
            order.orderType == OrderType.LimitIncrease
        ) {
            position = increasePosition(positionKey, order, 0, 0);
        } else if (
            order.orderType == OrderType.MarketDecrease ||
            order.orderType == OrderType.LimitDecrease
        ) {
            position = decreasePosition(positionKey, order, 0, 0);
        }

        emit OrderExecuted(id, 0, block.timestamp);
    }

    function increasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice,
        uint256 executionPriceDecimal
    ) internal returns (Position memory) {
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

        return position;
    }

    function decreasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice,
        uint256 executionPriceDecimal
    ) internal returns (Position memory) {
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

        return position;
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
