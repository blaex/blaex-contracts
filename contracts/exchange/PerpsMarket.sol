// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Authorization} from "../securities/Authorization.sol";
import {Funding} from "./Funding.sol";
import {Math} from "../utils/Math.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket, Authorization, ReentrancyGuard {
    uint256 public constant FACTOR = 10000;
    uint256 public constant LIQUIDATE_PERCENT = 90;

    IERC20 public immutable USDB;
    IPyth public immutable PYTH;
    IPerpsVault public immutable PERPS_VAULT;

    uint256 public minCollateral = 10 * 1e18;
    uint256 public maxCollateral = 2000 * 1e18;
    uint256 public maxLeverage = 50;
    uint256 public keeperFee = 1 * 1e18;
    uint256 public orderFee = 5;

    uint256 orderId = 1;
    uint256 positionId = 1;

    mapping(uint256 => Market) markets;
    mapping(uint256 => Order) orders;
    mapping(uint256 => Position) positions;
    mapping(address => uint256[]) accountPendingOrders;
    mapping(address => uint256[]) accountOpenPositions;
    mapping(bytes32 => uint256) openingPositionFlag;

    constructor(
        address _perpsVault,
        address _usdb,
        address _blastPoints,
        address _pyth,
        address _owner
    ) {
        USDB = IERC20(_usdb);
        PERPS_VAULT = IPerpsVault(_perpsVault);
        PYTH = IPyth(_pyth);
        IBlastPoints(_blastPoints).configurePointsOperator(_owner);
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
    }

    modifier onlyPerpsVault() {
        require(
            address(PERPS_VAULT) == msg.sender,
            "PerpsMarket: Only PerpsVault"
        );
        _;
    }

    // =====================================================================
    // Main functions
    // =====================================================================

    function depositCollateralCallback(
        uint256 _amount
    ) external onlyPerpsVault {
        USDB.transfer(address(PERPS_VAULT), _amount);
    }

    function createMarket(
        CreateMarketParams calldata params
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        require(params.id != 0, "Require id");
        Market storage market = markets[params.id];
        require(market.id == 0, "Market is exist");
        require(market.priceFeedId != "0", "Price feed not set");
        market.id = params.id;
        market.symbol = params.symbol;
        market.priceFeedId = params.priceFeedId;
        market.maxSkew = params.maxSkew; // 0: unlimited
        market.enable = true;

        emit MarketCreated(
            market.id,
            market.symbol,
            market.priceFeedId,
            market.maxSkew,
            market.enable
        );
    }

    function updateMarketSettings(
        uint256 _id,
        uint256 _maxSkew,
        bool _enable
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        Market storage market = markets[_id];
        require(market.id != 0, "Market is not exist");
        market.maxSkew = _maxSkew; // 0: unlimited
        market.enable = _enable;
        emit MarketUpdated(_id, _maxSkew, _enable);
    }

    function createOrder(
        CreateOrderParams calldata params
    ) external nonReentrant {
        bytes32 positionKey = keccak256(
            abi.encode(msg.sender, params.market, params.isLong)
        );
        uint256 flagId = openingPositionFlag[positionKey];
        Position memory position = positions[flagId];
        if (params.isIncrease) {
            Market memory market = markets[params.market];
            require(market.enable, "Market is not available for trading");
            require(
                params.collateralDeltaUsd >= minCollateral,
                "Under min collateral"
            );

            if (maxCollateral != 0) {
                require(
                    position.collateralInUsd + params.collateralDeltaUsd <=
                        maxCollateral,
                    "Over max collateral"
                );
            }

            if (market.maxSkew != 0 && market.skew != 0) {
                uint256 currentPrice = _indexPrice(market);
                int256 sizeInToken = int256(
                    (params.sizeDeltaUsd * 1e18) / currentPrice
                );
                // maxSkew available
                require(
                    market.skew > 0
                        ? (!params.isLong ||
                            Math.abs(market.skew + sizeInToken) <=
                            market.maxSkew)
                        : (params.isLong ||
                            Math.abs(market.skew - sizeInToken) <=
                            market.maxSkew),
                    "Over max market skew"
                );
            }

            uint256 leverage = (position.sizeInUsd + params.sizeDeltaUsd) /
                (position.collateralInUsd + params.collateralDeltaUsd);
            require(
                leverage <= maxLeverage && leverage >= 1,
                "Leverage invalid"
            );
        } else if (position.collateralInUsd > params.collateralDeltaUsd) {
            require(
                (position.sizeInUsd - params.sizeDeltaUsd) /
                    (position.collateralInUsd - params.collateralDeltaUsd) <=
                    maxLeverage,
                "Leverage invalid"
            );
        }

        uint256 orderFees = (params.sizeDeltaUsd * orderFee) / FACTOR;

        Order storage order = orders[orderId];
        order.account = msg.sender;
        order.market = params.market;
        order.sizeDeltaUsd = params.sizeDeltaUsd;
        order.collateralDeltaUsd = params.isIncrease
            ? params.collateralDeltaUsd - orderFees - keeperFee
            : params.collateralDeltaUsd;
        order.executionFees = keeperFee;
        order.triggerPrice = params.triggerPrice;
        order.acceptablePrice = params.acceptablePrice;
        order.isLong = params.isLong;
        order.isIncrease = params.isIncrease;
        order.orderFees = orderFees;
        order.submissionTime = block.timestamp;

        emit OrderSubmitted(
            orderId,
            order.account,
            order.market,
            order.isLong,
            order.collateralDeltaUsd,
            order.sizeDeltaUsd,
            order.triggerPrice,
            order.acceptablePrice,
            order.orderFees,
            order.executionFees
        );

        accountPendingOrders[msg.sender].push(orderId);
        orderId++;
    }

    function cancelOrder(uint256 _id) external nonReentrant {
        Order memory order = _verifyPendingOrder(_id);
        require(order.account == msg.sender, "Unauthorized");
        _cancelOrder(_id, order, "MANUAL");
    }

    function executeOrder(
        uint256 _id,
        bytes[] calldata _priceUpdateData
    ) external payable nonReentrant {
        Order memory order = _verifyPendingOrder(_id);

        PYTH.updatePriceFeeds{value: msg.value}(_priceUpdateData);
        (uint256 currentPrice, uint256 executionTime) = getExecutionPrice(
            order.market
        );

        require(executionTime > order.submissionTime, "not yet");
        if (
            order.triggerPrice == 0 &&
            block.timestamp - order.submissionTime > 60
        ) {
            _cancelOrder(_id, order, "EXPIRED");
            if (order.executionFees > 0) {
                USDB.transferFrom(
                    order.account,
                    address(this),
                    order.executionFees
                );
                USDB.transfer(msg.sender, order.executionFees);
            }
            return;
        }

        bool sign = order.isIncrease ? order.isLong : !order.isLong;
        require(
            (sign && currentPrice <= order.acceptablePrice) ||
                (!sign && currentPrice >= order.acceptablePrice),
            "Cannot fill order"
        );

        _removeFromArrayByValue(accountPendingOrders[order.account], _id);
        orders[_id].isExecuted = true;

        Funding.recomputeFunding(markets[order.market], currentPrice);

        bytes32 positionKey = keccak256(
            abi.encode(order.account, order.market, order.isLong)
        );

        uint256 flagId = openingPositionFlag[positionKey];
        if (order.isIncrease && flagId == 0) {
            flagId = positionId;
        }
        Position storage position = positions[flagId];

        if (order.isIncrease) {
            _increasePosition(positionKey, position, order, currentPrice);
        } else {
            _decreasePosition(positionKey, position, order, currentPrice);
        }

        emit OrderExecuted(_id, currentPrice, executionTime);
        emit PositionModified(
            position.id,
            position.account,
            position.market,
            position.isLong,
            position.sizeInUsd,
            position.sizeInToken,
            position.collateralInUsd,
            position.realisedPnl,
            position.paidFunding,
            position.latestInteractionFunding,
            position.paidFees,
            position.isClose,
            position.isLiquidated
        );
    }

    function liquidate(
        uint256 _positionId,
        bytes[] calldata _priceUpdateData
    ) external payable nonReentrant {
        Position storage position = positions[_positionId];
        require(position.id > 0, "No position found");
        require(!position.isClose, "Position is close");
        require(!position.isLiquidated, "Position is liquidated");

        Market storage market = markets[position.market];

        PYTH.updatePriceFeeds{value: msg.value}(_priceUpdateData);

        (
            uint256 collateralInUsd,
            ,
            int256 positionPnl,
            int256 fundingPnl
        ) = calculatePosition(position.id, false);

        uint256 totalPnl = Math.abs(positionPnl + fundingPnl);

        require(
            positionPnl + fundingPnl < 0 &&
                totalPnl >= (collateralInUsd * LIQUIDATE_PERCENT) / 100,
            "Cannot liquidate"
        );

        uint256 returnedCollateral = collateralInUsd;
        uint256 executionFees = keeperFee * 2;
        uint256 orderFees = (position.sizeInUsd * orderFee) / FACTOR;
        if (returnedCollateral > executionFees) {
            returnedCollateral -= executionFees;
            if (returnedCollateral > orderFees) {
                returnedCollateral -= orderFees;
            } else {
                orderFees = returnedCollateral;
                returnedCollateral = 0;
            }
        } else {
            executionFees = returnedCollateral;
            orderFees = 0;
            returnedCollateral = 0;
        }

        int256 pnl = returnedCollateral <= totalPnl
            ? int256(returnedCollateral) * -1
            : (positionPnl + fundingPnl);

        returnedCollateral -= Math.abs(pnl);

        _updateMarketSize(
            market,
            position.isLong
                ? int256(position.sizeInToken) * -1
                : int256(position.sizeInToken)
        );

        position.sizeInUsd = 0;
        position.collateralInUsd = 0;
        position.sizeInToken = 0;
        position.realisedPnl += returnedCollateral > 0
            ? positionPnl
            : (Math.abs(positionPnl) >= Math.abs(pnl) ? pnl : positionPnl);

        position.paidFunding += returnedCollateral > 0
            ? fundingPnl
            : (
                Math.abs(positionPnl) >= Math.abs(pnl)
                    ? int256(0)
                    : pnl - positionPnl
            );

        position.latestInteractionFunding = market.lastFundingValue;
        position.paidFees += executionFees + orderFees;
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

        emit PositionModified(
            position.id,
            position.account,
            position.market,
            position.isLong,
            position.sizeInUsd,
            position.sizeInToken,
            position.collateralInUsd,
            position.realisedPnl,
            position.paidFunding,
            position.latestInteractionFunding,
            position.paidFees,
            position.isClose,
            position.isLiquidated
        );

        emit PositionLiquidated(
            position.id,
            returnedCollateral,
            orderFees,
            executionFees
        );

        PERPS_VAULT.settleTrade(position.account, pnl, orderFees);
        if (returnedCollateral + executionFees > 0) {
            PERPS_VAULT.withdrawCollateral(
                position.account,
                returnedCollateral + executionFees
            );
        }
        if (returnedCollateral > 0)
            USDB.transfer(position.account, returnedCollateral);
        if (executionFees > 0) USDB.transfer(msg.sender, executionFees);
    }

    function updateSltp(
        uint256 _positionId,
        uint256 _sl,
        uint256 _tp
    ) external {
        Position storage position = positions[_positionId];
        require(position.id != 0, "Position is not exist");
        require(position.account == msg.sender, "Unauthorized");
        require(!position.isClose, "Position has been closed");
        Market memory market = markets[position.market];
        uint256 currentPrice = _indexPrice(market);
        require(
            _tp == 0 ||
                (position.isLong ? _tp > currentPrice : _tp < currentPrice),
            "Invalid take profit"
        );
        require(
            _sl == 0 ||
                (position.isLong ? _sl < currentPrice : _sl > currentPrice),
            "Invalid stop loss"
        );
        position.sl = _sl;
        position.tp = _tp;
        emit SltpUpdated(_positionId, _sl, _tp);
    }

    function executeSltp(
        uint256 _positionId,
        bytes[] calldata _priceUpdateData
    ) external payable {
        Position storage position = positions[_positionId];
        require(position.id != 0, "Position is not exist");
        require(!position.isClose, "Position has been closed");
        require(position.tp != 0 || position.sl != 0, "Need SL / TP");
        PYTH.updatePriceFeeds{value: msg.value}(_priceUpdateData);
        (uint256 currentPrice, uint256 executionTime) = getExecutionPrice(
            position.market
        );

        require(
            (position.tp > 0 &&
                (
                    position.isLong
                        ? position.tp <= currentPrice
                        : position.tp >= currentPrice
                )) ||
                (position.sl > 0 &&
                    (
                        position.isLong
                            ? position.sl >= currentPrice
                            : position.sl <= currentPrice
                    )),
            "Cannot execute"
        );

        bytes32 positionKey = keccak256(
            abi.encode(position.account, position.market, position.isLong)
        );
        Order memory order;
        order.sizeDeltaUsd = position.sizeInUsd;
        order.collateralDeltaUsd = position.collateralInUsd;
        order.executionFees = 2 * keeperFee;
        order.orderFees = (position.sizeInUsd * orderFee) / FACTOR;

        _decreasePosition(positionKey, position, order, currentPrice);

        emit SltpExecuted(position.id, currentPrice, executionTime);
        emit PositionModified(
            position.id,
            position.account,
            position.market,
            position.isLong,
            position.sizeInUsd,
            position.sizeInToken,
            position.collateralInUsd,
            position.realisedPnl,
            position.paidFunding,
            position.latestInteractionFunding,
            position.paidFees,
            position.isClose,
            position.isLiquidated
        );
    }

    // =====================================================================
    // Getters
    // =====================================================================

    function getExecutionPrice(
        uint256 _marketId
    ) public view returns (uint256 currentPrice, uint256 executionTime) {
        Market memory market = markets[_marketId];
        PythStructs.Price memory price = PYTH.getPrice(market.priceFeedId);
        currentPrice = _convertToUint(price, 18);
        executionTime = price.publishTime;
    }

    function indexPrice(
        uint256 _marketId
    ) public view returns (uint256 currentPrice) {
        Market memory market = markets[_marketId];
        require(market.id != 0, "Market is not exist");
        return _indexPrice(market);
    }

    function calculatePosition(
        uint256 _positionId,
        bool _unsafe
    )
        public
        view
        returns (
            uint256 collateralInUsd,
            uint256 sizeInUsd,
            int256 positionPnl,
            int256 fundingPnl
        )
    {
        Position memory position = positions[_positionId];
        Market memory market = markets[position.market];
        uint256 currentPrice;
        if (_unsafe) {
            currentPrice = _indexPrice(market);
        } else {
            (currentPrice, ) = getExecutionPrice(position.market);
        }

        collateralInUsd = position.collateralInUsd;
        sizeInUsd = (position.sizeInToken * currentPrice) / 10 ** 18;
        fundingPnl = Funding.getAccruedFunding(market, position, currentPrice);
        positionPnl = position.isLong
            ? int256(sizeInUsd) - int256(position.sizeInUsd)
            : int256(position.sizeInUsd) - int256(sizeInUsd);
    }

    function canLiquidate(uint256 _positionId) public view returns (bool) {
        (
            uint256 collateralInUsd,
            ,
            int256 positionPnl,
            int256 fundingPnl
        ) = calculatePosition(_positionId, true);

        uint256 totalPnl = Math.abs(positionPnl + fundingPnl);
        return
            positionPnl + fundingPnl < 0 &&
            totalPnl >= (collateralInUsd * LIQUIDATE_PERCENT) / 100;
    }

    function getMarket(uint256 _id) external view returns (Market memory) {
        return markets[_id];
    }

    function getPosition(uint256 _id) external view returns (Position memory) {
        return positions[_id];
    }

    function getOrder(uint256 _id) external view returns (Order memory) {
        return orders[_id];
    }

    function getOpenPositions(
        address _acccount
    ) external view returns (Position[] memory) {
        uint256[] memory positionIds = accountOpenPositions[_acccount];
        Position[] memory _positions = new Position[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            _positions[i] = positions[positionIds[i]];
        }
        return _positions;
    }

    function getPendingOrders(
        address _acccount
    ) external view returns (Order[] memory) {
        uint256[] memory orderIds = accountPendingOrders[_acccount];
        Order[] memory _orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            _orders[i] = orders[orderIds[i]];
        }
        return _orders;
    }

    // =====================================================================
    // Setters
    // =====================================================================

    function setKeeperFee(
        uint256 _keeperFee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        keeperFee = _keeperFee;
        emit KeeperFeeChanged(keeperFee);
    }

    function setOrderFee(
        uint256 _orderFee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        orderFee = _orderFee;
        emit OrderFeeChanged(orderFee);
    }

    function setMinCollateral(
        uint256 _minCollateral
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        require(minCollateral >= 10 * 1e18, "Invalid amount");
        minCollateral = _minCollateral;
        emit MinCollateralChanged(minCollateral);
    }

    function setMaxCollateral(
        uint256 _maxCollateral
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        maxCollateral = _maxCollateral;
        emit MaxCollateralChanged(maxCollateral);
    }

    function setMaxLeverage(
        uint256 _maxLeverage
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        maxLeverage = _maxLeverage;
        emit MaxLeverageChanged(maxLeverage);
    }

    // =====================================================================
    // Internal functions
    // =====================================================================

    function _indexPrice(
        Market memory market
    ) public view returns (uint256 currentPrice) {
        PythStructs.Price memory price = PYTH.getPriceUnsafe(
            market.priceFeedId
        );
        currentPrice = _convertToUint(price, 18);
    }

    function _increasePosition(
        bytes32 positionKey,
        Position storage position,
        Order memory order,
        uint256 executionPrice
    ) internal returns (Position memory) {
        USDB.transferFrom(
            order.account,
            address(this),
            order.collateralDeltaUsd + order.executionFees + order.orderFees
        );
        if (order.executionFees > 0)
            USDB.transfer(msg.sender, order.executionFees);
        PERPS_VAULT.depositCollateral(
            order.account,
            order.collateralDeltaUsd + order.orderFees
        );

        bool isNew = position.sizeInUsd == 0;
        uint256 increaseSizeDeltaToken = (order.sizeDeltaUsd * 10 ** 18) /
            executionPrice;
        if (isNew) {
            position.account = order.account;
            position.market = order.market;
            position.sizeInUsd = order.sizeDeltaUsd;
            position.sizeInToken = increaseSizeDeltaToken;
            position.collateralInUsd = order.collateralDeltaUsd;
            position.isLong = order.isLong;
            position.id = positionId;
            position.paidFees = order.orderFees;
            openingPositionFlag[positionKey] = positionId;
            accountOpenPositions[position.account].push(positionId);
            positionId++;
        } else {
            require(!position.isLiquidated, "Position is liquidated");
            position.sizeInUsd += order.sizeDeltaUsd;
            position.sizeInToken += increaseSizeDeltaToken;
            position.collateralInUsd += order.collateralDeltaUsd;
            position.paidFees += order.orderFees;
        }

        Market storage market = markets[position.market];
        _updateMarketSize(
            market,
            position.isLong
                ? int256(increaseSizeDeltaToken)
                : int256(increaseSizeDeltaToken) * -1
        );

        PERPS_VAULT.settleTrade(order.account, 0, order.orderFees);

        return position;
    }

    function _decreasePosition(
        bytes32 positionKey,
        Position storage position,
        Order memory order,
        uint256 executionPrice
    ) internal {
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
        int256 positionPnl = position.isLong
            ? int256(currentPositionSizeInUsd) - int256(position.sizeInUsd)
            : int256(position.sizeInUsd) - int256(currentPositionSizeInUsd);
        int256 realisedPnl = (positionPnl * int256(decreaseSizeDeltaToken)) /
            int256(position.sizeInToken);

        if (positionPnl + fundingPnl < 0) {
            require(
                Math.abs(positionPnl + fundingPnl) <
                    (position.collateralInUsd * LIQUIDATE_PERCENT) / 100,
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
        position.paidFees += order.orderFees;

        _updateMarketSize(
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
        uint256 receivedAmount = decreaseCollateralDeltaUsd - order.orderFees;

        int256 pnl = realisedPnl + fundingPnl;
        if (pnl >= 0) {
            receivedAmount += Math.abs(pnl);
        } else {
            if (Math.abs(pnl) > position.collateralInUsd)
                receivedAmount -= Math.abs(pnl);
        }
        PERPS_VAULT.settleTrade(position.account, pnl, order.orderFees);
        PERPS_VAULT.withdrawCollateral(position.account, receivedAmount);
        if (order.executionFees > 0)
            USDB.transfer(msg.sender, order.executionFees);
        USDB.transfer(position.account, receivedAmount - order.executionFees);
    }

    function _cancelOrder(
        uint256 id,
        Order memory order,
        bytes32 reason
    ) internal {
        orders[id].isCanceled = true;
        _removeFromArrayByValue(accountPendingOrders[order.account], id);
        emit OrderCanceled(id, reason);
    }

    function _verifyPendingOrder(
        uint256 id
    ) internal view returns (Order memory) {
        Order memory order = orders[id];
        require(order.account != address(0), "Order is not exist");
        require(!order.isCanceled, "Order has been canceled");
        require(!order.isExecuted, "Order has been executed");
        return order;
    }

    function _updateMarketSize(
        Market storage market,
        int256 sizeDelta
    ) internal {
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
