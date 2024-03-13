// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

import {Authorization} from "../securities/Authorization.sol";
import {Funding} from "../utils/Funding.sol";
import {Math} from "../utils/Math.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket, Authorization {
    IERC20 public constant USDB =
        IERC20(0x4300000000000000000000000000000000000003);
    // IERC20(0x4200000000000000000000000000000000000022);
    IPyth pyth;
    IPerpsVault perpsVault;

    bool public enableExchange = true;
    uint256 public protocolFee = 5;
    uint256 public constant FACTOR = 10000;
    mapping(uint256 => Market) markets;

    address feeReceiver;
    uint256 public keeperFee = 0;
    uint256 public liquidateFee = 5 * 1e18;

    uint256 orderId = 1;
    uint256 positionId = 1;
    mapping(uint256 => Order) orders;
    mapping(uint256 => Position) positions;
    mapping(address => uint256[]) accountOpenOrders;
    mapping(address => uint256[]) accountOpenPositions;
    mapping(bytes32 => uint256) openingPositionFlag;

    constructor(address _owner, address _perpsVault, address _pyth) {
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
        perpsVault = IPerpsVault(_perpsVault);
        pyth = IPyth(_pyth);
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

    function indexPrice(uint256 marketId) public view returns (uint256) {
        Market memory market = markets[marketId];
        require(market.priceFeedId != "0", "Price Feed not set");
        return _convertToUint(pyth.getPriceUnsafe(market.priceFeedId), 18);
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
        market.priceFeedId = params.priceFeedId;
        market.enable = true;
    }

    function setKeeperFee(
        uint256 _keeperFee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        keeperFee = _keeperFee;
    }

    function setProtocolFee(
        uint256 _protocolFee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        protocolFee = _protocolFee;
    }

    function setEnableExchange(
        bool _enableExchange
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        enableExchange = _enableExchange;
    }

    function liquidate(uint256 _positionId) external whenEnableExchange {
        Position memory position = positions[_positionId];
        require(position.id > 0, "No position found");
        require(!position.isClose, "Position is close");
        require(!position.isLiquidated, "Position is liquidated");

        Market storage market = markets[position.market];

        uint256 currentPrice = indexPrice(position.market);

        int256 fundingPnl = Funding.getAccruedFunding(
            market,
            position,
            currentPrice
        );

        uint256 currentPositionSizeInUsd = (position.sizeInToken *
            currentPrice) / 10 ** 18;

        //PnL
        int256 totalPnl = position.isLong
            ? int256(currentPositionSizeInUsd) - int256(position.sizeInUsd)
            : int256(position.sizeInUsd) - int256(currentPositionSizeInUsd);

        uint256 pnlAbs = Math.abs(totalPnl + fundingPnl);

        require(
            totalPnl + fundingPnl < 0 &&
                pnlAbs >= (position.collateralInUsd * 90) / 100,
            "Cannot liquidate"
        );

        uint256 remainingCollateral = position.collateralInUsd;
        int256 pnl = remainingCollateral <= pnlAbs
            ? int256(remainingCollateral) * -1
            : (totalPnl + fundingPnl);
        uint256 receivedAmount = remainingCollateral <= pnlAbs
            ? 0
            : remainingCollateral - pnlAbs;
        uint256 paidFees;
        uint256 executorFees;

        uint256 protocolFees = (position.sizeInUsd * protocolFee) / FACTOR;
        if (receivedAmount > liquidateFee) {
            paidFees += liquidateFee;
            receivedAmount -= liquidateFee;
            executorFees = liquidateFee;
            if (receivedAmount > protocolFees) {
                paidFees += protocolFees;
                receivedAmount -= protocolFees;
            } else {
                paidFees += receivedAmount;
                protocolFees = receivedAmount;
                receivedAmount = 0;
            }
        } else {
            paidFees += receivedAmount;
            executorFees = receivedAmount;
            protocolFees = 0;
            receivedAmount = 0;
        }

        _updateMarket(
            market,
            position.isLong
                ? int256(position.sizeInToken) * -1
                : int256(position.sizeInToken)
        );

        position.sizeInUsd = 0;
        position.collateralInUsd = 0;
        position.sizeInToken = 0;
        position.realisedPnl += remainingCollateral <= pnlAbs
            ? (Math.abs(totalPnl) > Math.abs(pnl) ? pnl : totalPnl)
            : totalPnl;
        position.paidFunding += remainingCollateral <= pnlAbs
            ? (Math.abs(totalPnl) > Math.abs(pnl) ? int256(0) : pnl - totalPnl)
            : fundingPnl;
        position.latestInteractionFunding = market.lastFundingValue;
        position.paidFees += paidFees;
        position.isClose = true;
        position.isLiquidated = true;

        bytes32 positionKey = keccak256(
            abi.encode(position.account, position.market, position.isLong)
        );
        openingPositionFlag[positionKey] = 0;
        _removeFromArrayByValue(
            accountOpenPositions[position.account],
            position.id
        );

        perpsVault.settleTrade(position.account, pnl, protocolFees);
        if (receivedAmount + executorFees > 0) {
            perpsVault.withdrawCollateral(
                position.account,
                receivedAmount + executorFees
            );
        }
        if (receivedAmount > 0) USDB.transfer(position.account, receivedAmount);
        if (executorFees > 0) USDB.transfer(msg.sender, executorFees);
    }

    function createOrder(
        CreateOrderParams calldata params
    ) external whenEnableExchange {
        require(
            markets[params.market].enable,
            "Market not available to trading"
        );
        require(
            params.collateralDeltaUsd > keeperFee,
            "Collateral amount must be greater than keeper fee"
        );

        require(
            params.collateralToken == address(USDB),
            "Collateral not support"
        );

        if (
            params.orderType == OrderType.MarketIncrease ||
            params.orderType == OrderType.LimitIncrease ||
            params.orderType == OrderType.MarketDecrease ||
            params.orderType == OrderType.LimitDecrease
        ) {
            // USDB.transferFrom(msg.sender, address(this), keeperFee);
        } else {
            revert("Order type is not supported");
        }

        uint256 protocolFees = (params.sizeDeltaUsd * protocolFee) / FACTOR;

        Order memory order;
        order.account = msg.sender;
        order.market = params.market;
        order.collateralToken = params.collateralToken;
        order.orderType = params.orderType;
        order.sizeDeltaUsd = params.sizeDeltaUsd;
        order.collateralDeltaUsd =
            params.collateralDeltaUsd -
            keeperFee -
            protocolFees;
        order.triggerPrice = params.triggerPrice;
        order.acceptablePrice = params.acceptablePrice;

        order.keeperFees = keeperFee;
        order.isLong = params.isLong;
        order.submissionTime = block.timestamp;
        order.protocolFees = protocolFees;
        order.id = orderId;

        uint256 currentPrice = indexPrice(order.market);

        require(
            (order.isLong && currentPrice <= order.acceptablePrice) ||
                (!order.isLong && currentPrice >= order.acceptablePrice),
            "Cannot fill order"
        );

        order.isFilled = true;
        order.executionPrice = currentPrice;
        order.executionTime = block.timestamp;

        orders[order.id] = order;
        accountOpenOrders[msg.sender].push(order.id);
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
            order.executionPrice,
            order.protocolFees,
            order.keeperFees
        );

        Funding.recomputeFunding(markets[order.market], currentPrice);

        bytes32 positionKey = keccak256(
            abi.encode(order.account, order.market, order.isLong)
        );

        Position memory position;
        if (
            order.orderType == OrderType.MarketIncrease ||
            order.orderType == OrderType.LimitIncrease
        ) {
            position = increasePosition(positionKey, order, currentPrice);
        } else if (
            order.orderType == OrderType.MarketDecrease ||
            order.orderType == OrderType.LimitDecrease
        ) {
            position = decreasePosition(positionKey, order, currentPrice);
        }

        emit PositionModified(
            position.id,
            position.account,
            position.market,
            position.collateralToken,
            position.sizeInUsd,
            position.sizeInToken,
            position.collateralInUsd,
            position.realisedPnl,
            position.paidFunding,
            position.latestInteractionFunding,
            position.paidFees,
            position.isLong,
            position.isClose
        );
    }

    // function cancelOrder(uint256 id) external whenEnableExchange {
    //     Order memory order = verifyOrder(id);
    //     require(
    //         order.account == msg.sender,
    //         "Unauthorize to access this order"
    //     );

    //     orders[id].isCanceled = true;
    //     orders[id].executionTime = block.timestamp;
    //     _removeFromArrayByValue(accountOpenOrders[order.account], id);
    //     emit OrderCanceled(id, block.timestamp);
    // }

    // function executeOrder(uint256 id) external {
    //     Order memory order = verifyOrder(id);
    //     orders[id].isFilled = true;
    //     orders[id].executionTime = block.timestamp;
    //     //TODO: validate price and block
    //     uint256 currentPrice = indexPrice(order.market);

    //     bytes32 positionKey = keccak256(
    //         abi.encode(order.account, order.market, order.isLong)
    //     );

    //     Position memory position;
    //     if (
    //         order.orderType == OrderType.MarketIncrease ||
    //         order.orderType == OrderType.LimitIncrease
    //     ) {
    //         position = increasePosition(positionKey, order, currentPrice);
    //     } else if (
    //         order.orderType == OrderType.MarketDecrease ||
    //         order.orderType == OrderType.LimitDecrease
    //     ) {
    //         position = decreasePosition(positionKey, order, currentPrice);
    //     }

    //     Funding.recomputeFunding(markets[order.market], currentPrice);

    //     emit PositionModified(
    //         position.id,
    //         position.account,
    //         position.market,
    //         position.collateralToken,
    //         position.sizeInUsd,
    //         position.sizeInToken,
    //         position.collateralInUsd,
    //         position.realisedPnl,
    //         position.paidFunding,
    //         position.latestInteractionFunding,
    //         position.isLong,
    //         position.isClose
    //     );
    //     emit OrderExecuted(id, currentPrice, block.timestamp);
    // }

    function increasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice
    ) internal returns (Position memory) {
        uint256 flagId = openingPositionFlag[positionKey];
        if (flagId == 0) {
            flagId = positionId;
        }
        Position storage position = positions[flagId];

        USDB.transferFrom(
            order.account,
            address(this),
            order.collateralDeltaUsd + order.keeperFees + order.protocolFees
        );
        if (order.keeperFees > 0) USDB.transfer(msg.sender, order.keeperFees);
        perpsVault.depositCollateral(
            order.account,
            order.collateralDeltaUsd + order.protocolFees
        );

        bool isNew = position.sizeInUsd == 0;
        uint256 increaseSizeDeltaToken = (order.sizeDeltaUsd * 10 ** 18) /
            executionPrice;
        if (isNew) {
            position.account = order.account;
            position.market = order.market;
            position.collateralToken = order.collateralToken;
            position.sizeInUsd = order.sizeDeltaUsd;
            position.sizeInToken = increaseSizeDeltaToken;
            position.collateralInUsd = order.collateralDeltaUsd;
            position.isLong = order.isLong;
            position.id = positionId;
            position.paidFees = order.protocolFees;
            openingPositionFlag[positionKey] = positionId;
            accountOpenPositions[position.account].push(positionId);
            positionId += 1;
        } else {
            require(!position.isLiquidated, "Position is liquidated");
            position.sizeInUsd += order.sizeDeltaUsd;
            position.sizeInToken += increaseSizeDeltaToken;
            position.collateralInUsd += order.collateralDeltaUsd;
            position.paidFees += order.protocolFees;
        }

        Market storage market = markets[position.market];
        _updateMarket(
            market,
            position.isLong
                ? int256(increaseSizeDeltaToken)
                : int256(increaseSizeDeltaToken) * -1
        );

        perpsVault.settleTrade(order.account, 0, order.protocolFees);

        return position;
    }

    function decreasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice
    ) internal returns (Position memory) {
        uint256 flagId = openingPositionFlag[positionKey];
        Position storage position = positions[flagId];

        require(position.id > 0, "No open position found");
        require(!position.isLiquidated, "Position is liquidated");
        Market storage market = markets[position.market];

        int256 fundingPnl = Funding.getAccruedFunding(
            market,
            position,
            executionPrice
        );

        uint256 decreaseSizeDeltaUsd = order.sizeDeltaUsd > position.sizeInUsd
            ? position.sizeInUsd
            : order.sizeDeltaUsd;
        uint256 decreaseSizeDeltaToken = (position.sizeInToken *
            decreaseSizeDeltaUsd) / position.sizeInUsd;
        uint256 decreaseCollateralDeltaUsd = order.collateralDeltaUsd >
            position.collateralInUsd ||
            decreaseSizeDeltaUsd == position.sizeInUsd
            ? position.collateralInUsd
            : order.collateralDeltaUsd;
        uint256 currentPositionSizeInUsd = (position.sizeInToken *
            executionPrice) / 10 ** 18;

        //PnL
        int256 totalPnl = position.isLong
            ? int256(currentPositionSizeInUsd) - int256(position.sizeInUsd)
            : int256(position.sizeInUsd) - int256(currentPositionSizeInUsd);
        int256 realisedPnl = (totalPnl * int256(decreaseSizeDeltaToken)) /
            int256(position.sizeInToken);

        if (totalPnl + fundingPnl < 0) {
            require(
                Math.abs(totalPnl + fundingPnl) <
                    (position.collateralInUsd * 90) / 100,
                "Position has been set to be liquidated"
            );
        }

        //Update value
        position.sizeInUsd -= decreaseSizeDeltaUsd;
        position.collateralInUsd -= decreaseCollateralDeltaUsd;
        position.sizeInToken -= decreaseSizeDeltaToken;
        position.realisedPnl += realisedPnl;
        position.paidFunding += fundingPnl;
        position.latestInteractionFunding = market.lastFundingValue;
        position.paidFees += order.protocolFees;

        _updateMarket(
            market,
            position.isLong
                ? int256(decreaseSizeDeltaToken) * -1
                : int256(decreaseSizeDeltaToken)
        );

        if (position.sizeInUsd == 0) {
            position.isClose = true;
            openingPositionFlag[positionKey] = 0;
            _removeFromArrayByValue(
                accountOpenPositions[position.account],
                position.id
            );
        }

        //transfer collateral & pnl
        uint256 receivedAmount = decreaseCollateralDeltaUsd -
            order.protocolFees;

        int256 pnl = realisedPnl + fundingPnl;
        if (pnl >= 0) {
            receivedAmount += Math.abs(pnl);
        } else {
            if (Math.abs(pnl) > position.collateralInUsd)
                receivedAmount -= Math.abs(pnl);
        }
        perpsVault.settleTrade(order.account, pnl, order.protocolFees);
        perpsVault.withdrawCollateral(order.account, receivedAmount);
        if (order.keeperFees > 0) USDB.transfer(msg.sender, order.keeperFees);
        USDB.transfer(order.account, receivedAmount - order.keeperFees);

        return position;
    }

    function getMarket(uint256 id) external view returns (Market memory) {
        return markets[id];
    }

    function getOrder(uint256 id) external view returns (Order memory) {
        return orders[id];
    }

    function getPosition(uint256 id) external view returns (Position memory) {
        return positions[id];
    }

    function getOpenOrders(
        address account
    ) external view returns (Order[] memory) {
        uint256[] memory orderIds = accountOpenOrders[account];
        Order[] memory _orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            _orders[i] = orders[orderIds[i]];
        }

        return _orders;
    }

    function getOpenPositions(
        address acccount
    ) external view returns (Position[] memory) {
        uint256[] memory positionIds = accountOpenPositions[acccount];
        Position[] memory _positions = new Position[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            _positions[i] = positions[positionIds[i]];
        }

        return _positions;
    }

    function verifyOrder(uint256 id) internal view returns (Order memory) {
        require(id > 0 && id < orderId, "Invalid order id");

        Order memory order = orders[id];
        require(!order.isFilled, "Order already filled");
        require(!order.isCanceled, "Order already canceled");

        return order;
    }

    function _updateMarket(Market storage market, int256 sizeDelta) internal {
        market.size += Math.abs(sizeDelta);
        market.skew += sizeDelta;
    }

    function _removeFromArrayByValue(
        uint256[] storage arr,
        uint256 value
    ) internal {
        bool found = false;
        for (uint i = 0; i < arr.length - 1; i++) {
            if (!found && arr[i] == value) {
                found = true;
            }

            if (found) {
                arr[i] = arr[i + 1];
            }
        }

        if (found || arr[arr.length - 1] == value) {
            arr.pop();
        }
    }

    function _convertToUint(
        PythStructs.Price memory price,
        uint8 targetDecimals
    ) private pure returns (uint256) {
        if (price.price < 0 || price.expo > 0 || price.expo < -255) {
            revert();
        }

        uint8 priceDecimals = uint8(uint32(-1 * price.expo));

        if (targetDecimals >= priceDecimals) {
            return
                uint(uint64(price.price)) *
                10 ** uint32(targetDecimals - priceDecimals);
        } else {
            return
                uint(uint64(price.price)) /
                10 ** uint32(priceDecimals - targetDecimals);
        }
    }
}
