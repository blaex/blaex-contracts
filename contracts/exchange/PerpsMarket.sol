// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Authorization} from "../securities/Authorization.sol";
import {Funding} from "../utils/Funding.sol";
import {Math} from "../utils/Math.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket, Authorization, ReentrancyGuard {
    uint256 public constant FACTOR = 10000;

    IERC20 public immutable USDB;
    IPyth public immutable PYTH;
    IPerpsVault public immutable PERPS_VAULT;

    uint256 public minCollateral = 10 * 1e18;
    uint256 public maxSize = 10000 * 1e18;
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
        address _usdb,
        address _blastPoints,
        address _owner,
        address _perpsVault,
        address _pyth
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

    function getPrice(
        uint256 marketId
    ) public view returns (uint256 currentPrice, uint256 executionTime) {
        Market memory market = markets[marketId];
        require(market.priceFeedId != "0", "Price feed not set");
        PythStructs.Price memory price = PYTH.getPrice(market.priceFeedId);
        currentPrice = _convertToUint(price, 18);
        executionTime = price.publishTime;
    }

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
        uint256 _orderFee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        orderFee = _orderFee;
    }

    function setMinCollateral(
        uint256 _minCollateral
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        minCollateral = _minCollateral;
    }

    function setMaxSize(
        uint256 _maxSize
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        maxSize = _maxSize;
    }

    function setMaxLeverage(
        uint256 _maxLeverage
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        maxLeverage = _maxLeverage;
    }

    function liquidate(uint256 _positionId) external nonReentrant {
        Position storage position = positions[_positionId];
        require(position.id > 0, "No position found");
        require(!position.isClose, "Position is close");
        require(!position.isLiquidated, "Position is liquidated");

        Market storage market = markets[position.market];

        (uint256 currentPrice, ) = getPrice(position.market);

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
        uint256 returnedCollateral = remainingCollateral <= pnlAbs
            ? 0
            : remainingCollateral - pnlAbs;

        uint256 executionFees;
        uint256 orderFees = (position.sizeInUsd * orderFee) / FACTOR;
        if (returnedCollateral > keeperFee) {
            returnedCollateral -= keeperFee;
            executionFees = keeperFee;
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
            ? (Math.abs(totalPnl) >= Math.abs(pnl) ? pnl : totalPnl)
            : totalPnl;
        position.paidFunding += remainingCollateral <= pnlAbs
            ? (Math.abs(totalPnl) >= Math.abs(pnl) ? int256(0) : pnl - totalPnl)
            : fundingPnl;
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

    function createOrder(
        CreateOrderParams calldata params
    ) external nonReentrant {
        require(
            markets[params.market].enable,
            "Market not available to trading"
        );

        bytes32 positionKey = keccak256(
            abi.encode(msg.sender, params.market, params.isLong)
        );

        uint256 flagId = openingPositionFlag[positionKey];

        Position memory position = positions[flagId];
        if (params.isIncrease) {
            require(
                params.collateralDeltaUsd >= minCollateral,
                "Need more collateral amount"
            );

            require(
                position.sizeInUsd + params.sizeDeltaUsd <= maxSize,
                "Over max size"
            );
            require(
                (position.sizeInUsd + params.sizeDeltaUsd) /
                    (position.collateralInUsd + params.collateralDeltaUsd) <=
                    maxLeverage,
                "Over max leverage"
            );
        } else {
            require(
                (position.sizeInUsd - params.sizeDeltaUsd) /
                    (position.collateralInUsd - params.collateralDeltaUsd) <=
                    maxLeverage,
                "Over max leverage"
            );
        }

        uint256 orderFees = (params.sizeDeltaUsd * orderFee) / FACTOR;

        Order memory order;
        order.account = msg.sender;
        order.market = params.market;
        order.sizeDeltaUsd = params.sizeDeltaUsd;
        order.collateralDeltaUsd =
            params.collateralDeltaUsd -
            orderFees -
            keeperFee;
        order.executionFees = keeperFee;
        order.triggerPrice = params.triggerPrice;
        order.acceptablePrice = params.acceptablePrice;
        order.isLong = params.isLong;
        order.isIncrease = params.isIncrease;
        order.orderFees = orderFees;
        order.submissionTime = block.timestamp;

        emit OrderSubmitted(
            order.triggerPrice == 0 ? 0 : orderId,
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

        if (params.triggerPrice == 0) {} else {}

        accountPendingOrders[msg.sender].push(orderId);
    }

    function cancelOrder(uint256 id) external nonReentrant {
        Order memory order = verifyPendingOrder(id);
        require(order.account == msg.sender, "Unauthorized");

        _removeFromArrayByValue(accountPendingOrders[order.account], id);
        orders[id].isCanceled = true;
        emit OrderCanceled(id, "MANUAL");
    }

    function executeOrder(
        uint256 id,
        bytes[] calldata priceUpdateData
    ) external payable nonReentrant {
        Order memory order = verifyPendingOrder(id);

        PYTH.updatePriceFeeds{value: msg.value}(priceUpdateData);

        (uint256 currentPrice, uint256 executionTime) = getPrice(order.market);

        require(executionTime > order.submissionTime, "not yet");

        if (
            order.triggerPrice == 0 &&
            block.timestamp - order.submissionTime > 60
        ) {
            _removeFromArrayByValue(accountPendingOrders[order.account], id);
            orders[id].isCanceled = true;

            if (order.executionFees > 0) {
                USDB.transferFrom(
                    order.account,
                    address(this),
                    order.executionFees
                );
                USDB.transfer(msg.sender, order.executionFees);
            }

            emit OrderCanceled(id, "EXPIRED");
            return;
        }

        require(
            (order.isLong && currentPrice <= order.acceptablePrice) ||
                (!order.isLong && currentPrice >= order.acceptablePrice),
            "Cannot fill order"
        );

        _removeFromArrayByValue(accountPendingOrders[order.account], id);
        orders[id].isExecuted = true;

        Funding.recomputeFunding(markets[order.market], currentPrice);

        Position memory position;
        bytes32 positionKey = keccak256(
            abi.encode(order.account, order.market, order.isLong)
        );

        if (order.isIncrease) {
            position = increasePosition(positionKey, order, currentPrice);
        } else {
            position = decreasePosition(positionKey, order, currentPrice);
        }

        emit OrderExecuted(id, currentPrice, executionTime);
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
            positionId += 1;
        } else {
            require(!position.isLiquidated, "Position is liquidated");
            position.sizeInUsd += order.sizeDeltaUsd;
            position.sizeInToken += increaseSizeDeltaToken;
            position.collateralInUsd += order.collateralDeltaUsd;
            position.paidFees += order.orderFees;
        }

        Market storage market = markets[position.market];
        _updateMarket(
            market,
            position.isLong
                ? int256(increaseSizeDeltaToken)
                : int256(increaseSizeDeltaToken) * -1
        );

        PERPS_VAULT.settleTrade(order.account, 0, order.orderFees);

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
        position.paidFees += order.orderFees;

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
        uint256 receivedAmount = decreaseCollateralDeltaUsd - order.orderFees;

        int256 pnl = realisedPnl + fundingPnl;
        if (pnl >= 0) {
            receivedAmount += Math.abs(pnl);
        } else {
            if (Math.abs(pnl) > position.collateralInUsd)
                receivedAmount -= Math.abs(pnl);
        }
        PERPS_VAULT.settleTrade(order.account, pnl, order.orderFees);
        PERPS_VAULT.withdrawCollateral(order.account, receivedAmount);
        if (order.executionFees > 0)
            USDB.transfer(msg.sender, order.executionFees);
        USDB.transfer(order.account, receivedAmount - order.executionFees);

        return position;
    }

    function getMarket(uint256 id) external view returns (Market memory) {
        return markets[id];
    }

    function getPosition(uint256 id) external view returns (Position memory) {
        return positions[id];
    }

    function getOrder(uint256 id) external view returns (Order memory) {
        return orders[id];
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

    function getPendingOrders(
        address acccount
    ) external view returns (Order[] memory) {
        uint256[] memory orderIds = accountPendingOrders[acccount];
        Order[] memory _orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            _orders[i] = orders[orderIds[i]];
        }
        return _orders;
    }

    function verifyPendingOrder(
        uint256 id
    ) internal view returns (Order memory) {
        Order memory order = orders[id];
        require(order.account != address(0), "Order is not exist");
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
