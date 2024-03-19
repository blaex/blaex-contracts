// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IPerpsMarket} from "../interfaces/IPerpsMarket.sol";

import {Authorization} from "../securities/Authorization.sol";
import {Math} from "../utils/Math.sol";
import "../interfaces/IPerpsMarket.sol";

library Funding {
    function calculateNextFunding(
        IPerpsMarket.Market memory market,
        uint price
    ) internal view returns (int nextFunding) {
        nextFunding =
            market.lastFundingValue +
            unrecordedFunding(market, price);
    }

    function unrecordedFunding(
        IPerpsMarket.Market memory market,
        uint price
    ) internal view returns (int) {
        int fundingRate = currentFundingRate(market);
        // note the minus sign: funding flows in the opposite direction to the skew.
        int avgFundingRate = -(market.lastFundingRate + fundingRate) / 2;

        return
            (((avgFundingRate * proportionalElapsed(market)) / 1e18) *
                int(price)) / 1e18;
    }

    function currentFundingRate(
        IPerpsMarket.Market memory market
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
            ((currentFundingVelocity(market) * proportionalElapsed(market)) /
                1e18);
    }

    function currentFundingVelocity(
        IPerpsMarket.Market memory market
    ) internal pure returns (int) {
        int maxFundingVelocity = 9000000000000000000;
        int skewScale = 100000000000000000000000;
        // Avoid a panic due to div by zero. Return 0 immediately.
        // if (skewScale == 0) {
        //     return 0;
        // }
        // Ensures the proportionalSkew is between -1 and 1.
        int pSkew = (market.skew * 1e18) / skewScale;
        int pSkewBounded = Math.min(Math.max(-1e18, pSkew), 1e18);
        return (pSkewBounded * maxFundingVelocity) / 1e18;
    }

    function proportionalElapsed(
        IPerpsMarket.Market memory market
    ) internal view returns (int) {
        // even though timestamps here are not D18, divDecimal multiplies by 1e18 to preserve decimals into D18
        return
            int(((block.timestamp - market.lastFundingTime) * 1e18) / 1 days);
    }

    function getAccruedFunding(
        IPerpsMarket.Market memory market,
        IPerpsMarket.Position memory position,
        uint price
    ) internal view returns (int accruedFunding) {
        int nextFunding = calculateNextFunding(market, price);
        int netFundingPerUnit = nextFunding - position.latestInteractionFunding;
        int size = position.isLong
            ? int(position.sizeInToken)
            : int(position.sizeInToken) * -1;
        accruedFunding = (size * netFundingPerUnit) / 1e18;
    }

    event FundingRecomputed(
        int fundingRate,
        int fundingValue,
        uint fundingTime
    );

    function recomputeFunding(
        IPerpsMarket.Market storage market,
        uint price
    ) internal returns (int fundingRate, int fundingValue) {
        fundingRate = currentFundingRate(market);
        fundingValue = calculateNextFunding(market, price);

        market.lastFundingRate = fundingRate;
        market.lastFundingValue = fundingValue;
        market.lastFundingTime = block.timestamp;

        emit FundingRecomputed(fundingRate, fundingValue, block.timestamp);

        return (fundingRate, fundingValue);
    }
}
