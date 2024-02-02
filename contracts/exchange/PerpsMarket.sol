// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

import {Authorization} from "../securities/Authorization.sol";
import "../interfaces/IPerpsMarket.sol";

contract PerpsMarket is IPerpsMarket, Authorization {
    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);
    IPyth pyth;
    IPerpsVault perpsVault;

    bool public enableExchange = true;
    uint256 public protocolFee = 500;
    uint256 public constant FACTOR = 10000;
    mapping(uint256 => Market) markets;

    address feeReceiver;
    uint256 public keeperFee;

    uint256 orderId = 1;
    uint256 positionId = 1;
    mapping(uint256 => Order) orders;
    mapping(uint256 => Position) positions;
    mapping(address => uint256[]) openOrders;
    mapping(address => uint256[]) openPositions;
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
        return _convertToUint(pyth.getPrice(market.priceFeedId), 18);
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

    function createOrder(
        CreateOrderParams calldata params
    ) external payable whenEnableExchange {
        require(
            markets[params.market].enable,
            "Market not available to trading"
        );
        require(params.receiver != address(0), "Invalid receiver");
        require(
            params.collateralDeltaUsd > keeperFee,
            "Collateral amout must be greater than keeper fee"
        );

        if (
            params.orderType == OrderType.MarketIncrease ||
            params.orderType == OrderType.LimitIncrease ||
            params.orderType == OrderType.MarketDecrease ||
            params.orderType == OrderType.LimitDecrease
        ) {
            USDB.transferFrom(msg.sender, address(this), keeperFee);
        } else {
            revert("Order type is not supported");
        }

        Order memory order;
        order.account = msg.sender;
        order.market = params.market;
        order.collateralToken = params.collateralToken;
        order.orderType = params.orderType;
        order.sizeDeltaUsd = params.sizeDeltaUsd;
        order.collateralDeltaUsd = params.collateralDeltaUsd - keeperFee;
        order.triggerPrice = params.triggerPrice;
        order.acceptablePrice = params.acceptablePrice;
        order.keeperFee = keeperFee;
        order.callbackGasLimit = params.callbackGasLimit;
        order.minOutputAmount = params.minOutputAmount;
        order.isLong = params.isLong;
        order.id = orderId;

        orders[order.id] = order;
        openOrders[msg.sender].push(order.id);
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
            order.keeperFee
        );
    }

    function cancelOrder(uint256 id) external whenEnableExchange {
        Order memory order = verifyOrder(id);
        require(
            order.account == msg.sender,
            "Unauthorize to access this order"
        );

        orders[id].isCanceled = true;
        _removeFromArrayByValue(openOrders[order.account], id);
        emit OrderCanceled(id);
    }

    function executeOrder(
        uint256 id,
        ExecuteOrderParams memory params
    ) external {
        Order memory order = verifyOrder(id);
        orders[id].isFilled = true;

        //TODO: validate price and block
        uint256 currentPrice = indexPrice(order.market);

        //Transfer fee
        USDB.transferFrom(address(this), msg.sender, order.keeperFee);

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

        _recomputeFunding(markets[order.market], currentPrice);

        emit OrderExecuted(id, 0, block.timestamp);
    }

    function increasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice
    ) internal returns (Position memory) {
        Position memory position = positions[openingPositionFlag[positionKey]];

        USDB.transferFrom(
            order.account,
            address(this),
            order.collateralDeltaUsd
        );
        perpsVault.depositCollateral(order.account, order.collateralDeltaUsd);

        bool isNew = position.sizeInUsd == 0 && !position.isClose;
        uint256 sizeInToken = (order.sizeDeltaUsd * 10 ** 18) / executionPrice;
        if (isNew) {
            position.account = order.account;
            position.market = order.market;
            position.collateralToken = order.collateralToken;
            position.sizeInUsd = order.sizeDeltaUsd;
            position.sizeInToken = sizeInToken;
            position.collateralInUsd = order.collateralDeltaUsd;
            position.isLong = order.isLong;
            position.id = positionId;

            positions[position.id] = position;
            openPositions[position.account].push(position.id);
            positionId += 1;
        } else {
            position.sizeInUsd += order.sizeDeltaUsd;
            position.sizeInToken += sizeInToken;
            position.collateralInUsd += order.collateralDeltaUsd;
        }

        Market storage market = markets[position.market];

        market.size += sizeInToken;
        int256 sizeDelta;
        if (position.isLong) {
            sizeDelta = int256(sizeInToken);
        } else {
            sizeDelta = int256(sizeInToken) * -1;
        }
        market.skew += sizeDelta;

        positions[openingPositionFlag[positionKey]] = position;

        uint256 fees = (order.sizeDeltaUsd * protocolFee) / FACTOR;
        perpsVault.settleTrade(order.account, 0, fees);

        return position;
    }

    function decreasePosition(
        bytes32 positionKey,
        Order memory order,
        uint256 executionPrice
    ) internal returns (Position memory) {
        Position memory position = positions[openingPositionFlag[positionKey]];

        int256 fundingPnl = _accruedFunding(position, executionPrice);

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
            executionPrice) / 10 ** 18;

        //PnL
        int256 totalPnl = position.isLong
            ? int256(currentPositionSizeInUsd - position.sizeInUsd)
            : int256(position.sizeInUsd - currentPositionSizeInUsd);
        int256 pricePnl = (totalPnl * int256(decreaseSizeDeltaToken)) /
            int256(position.sizeInToken);

        //Update value
        position.sizeInUsd -= decreaseSizeDeltaUsd;
        position.collateralInUsd -= decreaseCollateralDeltaUsd;
        position.sizeInToken -= decreaseSizeDeltaToken;
        position.realisedPnl += pricePnl;

        Market storage market = markets[position.market];

        market.size += decreaseSizeDeltaToken;
        int256 sizeDelta;
        if (position.isLong) {
            sizeDelta = int256(decreaseSizeDeltaToken) * -1;
        } else {
            sizeDelta = int256(decreaseSizeDeltaToken);
        }
        market.skew += sizeDelta;

        position.paidFunding += fundingPnl;
        position.latestInteractionFunding = market.lastFundingValue;

        if (position.sizeInUsd == 0) {
            position.isClose = true;
            _removeFromArrayByValue(
                openPositions[position.account],
                position.id
            );
        }
        uint256 flag;
        {
            flag = openingPositionFlag[positionKey];
            positions[flag] = position;
        }

        //transfer collateral & pnl
        uint256 fees = (order.sizeDeltaUsd * protocolFee) / FACTOR;
        uint256 receivedAmount = order.collateralDeltaUsd - fees;
        int256 pnl = pricePnl + fundingPnl;
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

    function getOrder(uint256 id) external view returns (Order memory) {
        return orders[id];
    }

    function getPosition(uint256 id) external view returns (Position memory) {
        return positions[id];
    }

    function getOpenOrders(
        address account
    ) external view returns (Order[] memory) {
        uint256[] memory orderIds = openOrders[account];
        Order[] memory _orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            _orders[i] = orders[orderIds[i]];
        }

        return _orders;
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

    function getOpeningPositions(
        address acccount
    ) external view returns (Position[] memory) {
        uint256[] memory positionIds = openPositions[acccount];
        Position[] memory _positions = new Position[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            _positions[i] = positions[positionIds[i]];
        }

        return _positions;
    }

    function verifyOrder(uint256 id) internal returns (Order memory) {
        require(id > 0 && id < orderId, "Invalid order id");

        Order memory order = orders[id];
        require(!order.isFilled, "Order already filled");
        require(!order.isCanceled, "Order already canceled");

        return order;
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

    function _calculateNextFunding(
        Market storage market,
        uint price
    ) internal view returns (int nextFunding) {
        nextFunding =
            market.lastFundingValue +
            _unrecordedFunding(market, price);
    }

    function _unrecordedFunding(
        Market storage market,
        uint price
    ) internal view returns (int) {
        int fundingRate = _currentFundingRate(market);
        // note the minus sign: funding flows in the opposite direction to the skew.
        int avgFundingRate = -(market.lastFundingRate + fundingRate) / 2;

        return
            (((avgFundingRate * _proportionalElapsed(market)) / 1e18) *
                int(price)) / 1e18;
    }

    function _currentFundingRate(
        Market storage market
    ) internal view returns (int) {
        // calculations:
        //  - velocity          = proportional_skew * max_funding_velocity
        //  - proportional_skew = skew / skew_scale
        //
        // example:
        //  - prev_funding_rate     = 0
        //  - prev_velocity         = 0.0025
        //  - time_delta            = 29,000s
        //  - max_funding_velocity  = 0.025 (2.5%)
        //  - skew                  = 300
        //  - skew_scale            = 10,000
        //
        // note: prev_velocity just refs to the velocity _before_ modifying the market skew.
        //
        // funding_rate = prev_funding_rate + prev_velocity * (time_delta / seconds_in_day)
        // funding_rate = 0 + 0.0025 * (29,000 / 86,400)
        //              = 0 + 0.0025 * 0.33564815
        //              = 0.00083912
        return
            market.lastFundingRate +
            ((_currentFundingVelocity(market) * _proportionalElapsed(market)) /
                1e18);
    }

    function _currentFundingVelocity(
        Market storage self
    ) internal view returns (int) {
        int maxFundingVelocity = 9000000000000000000;
        int skewScale = 100000000000000000000000;
        // Avoid a panic due to div by zero. Return 0 immediately.
        // if (skewScale == 0) {
        //     return 0;
        // }
        // Ensures the proportionalSkew is between -1 and 1.
        int pSkew = (self.skew * 1e18) / skewScale;
        int pSkewBounded = _min(_max(-1e18, pSkew), 1e18);
        return (pSkewBounded * maxFundingVelocity) / 1e18;
    }

    function _proportionalElapsed(
        Market storage market
    ) internal view returns (int) {
        // even though timestamps here are not D18, divDecimal multiplies by 1e18 to preserve decimals into D18
        return
            int(((block.timestamp - market.lastFundingTime) * 1e18) / 1 days);
    }

    function _accruedFunding(
        Position memory position,
        uint price
    ) internal view returns (int accruedFunding) {
        int nextFunding = _calculateNextFunding(
            markets[position.market],
            price
        );
        int netFundingPerUnit = nextFunding - position.latestInteractionFunding;
        int size = position.isLong
            ? int(position.sizeInToken)
            : int(position.sizeInToken) * -1;
        accruedFunding = (size * netFundingPerUnit) / 1e18;
    }

    function _recomputeFunding(
        Market storage market,
        uint price
    ) internal returns (int fundingRate, int fundingValue) {
        fundingRate = _currentFundingRate(market);
        fundingValue = _calculateNextFunding(market, price);

        market.lastFundingRate = fundingRate;
        market.lastFundingValue = fundingValue;
        market.lastFundingTime = block.timestamp;

        return (fundingRate, fundingValue);
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

    function _abs(int256 x) internal pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
    }

    function _max(int x, int y) internal pure returns (int) {
        return x < y ? y : x;
    }

    function _max(uint x, uint y) internal pure returns (uint) {
        return x < y ? y : x;
    }

    function _min(int x, int y) internal pure returns (int) {
        return x < y ? x : y;
    }

    function _min(uint x, uint y) internal pure returns (uint) {
        return x < y ? x : y;
    }
}
