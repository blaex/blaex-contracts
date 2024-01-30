// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBLI} from "./interfaces/IBLI.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {YieldERC20} from "./YieldERC20.sol";
import {Authorization} from "./securities/Authorization.sol";

contract BLI is YieldERC20, IBLI, Authorization, ReentrancyGuard {
    using Address for address;
    uint256 constant FACTOR = 10000;

    DailyStatistic dailyStatistic;

    uint256 totalPooledToken;
    address feeReceiver;
    uint256 fee;

    IERC20 internal immutable USDB;

    constructor(
        address _owner,
        address _feeReceiver,
        address _usdb
    ) YieldERC20("Blaex Liquidity Index", "BLI") {
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
        feeReceiver = _feeReceiver;
        fee = 0;
        USDB = IERC20(_usdb);
    }

    // =====================================================================
    // Main functions
    // =====================================================================
    /**
     * @dev Process user deposit, mints liquid tokens and increase the pool buffer
     */
    function deposit(uint256 amount) external nonReentrant {
        USDB.transferFrom(msg.sender, address(this), amount);

        uint256 sharesAmount = getSharesByPooledToken(amount);
        if (sharesAmount == 0) {
            sharesAmount = amount;
        }

        totalPooledToken += amount;
        _mintShares(msg.sender, sharesAmount);
        _updateDailyStatistic({
            _depositAmount: amount,
            _withdrawAmount: 0,
            _feeAmount: 0,
            _pnlAmount: 0,
            _yieldAmount: 0
        });
        emit Deposit(msg.sender, amount);

        _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    }

    /**
     * @dev Process withdraw, burn stRon and withdraw from delegate batch the corresponding amount of Token to the user
     *
     * Emits `Withdraw` event
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Not enough balance");

        //Burn
        uint256 sharesAmount = getSharesByPooledToken(amount);
        _burnShares(msg.sender, sharesAmount);
        totalPooledToken -= amount;

        _updateDailyStatistic({
            _depositAmount: 0,
            _withdrawAmount: amount,
            _feeAmount: 0,
            _pnlAmount: 0,
            _yieldAmount: 0
        });
        emit Withdraw(msg.sender, amount);
    }

    // =====================================================================
    // Getter
    // =====================================================================
    function getFee() external view override returns (uint256) {
        return fee;
    }

    function getFactor() external pure override returns (uint256) {
        return FACTOR;
    }

    function getFeeReceiver() external view returns (address) {
        return feeReceiver;
    }

    // =====================================================================
    // Setter
    // =====================================================================
    function setFee(
        uint256 _fee
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        fee = _fee;
        emit UpdatedFee(_fee);
    }

    function setFeeReceiver(
        address _feeReceiver
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        feeReceiver = _feeReceiver;
        emit UpdatedFeeReceiver(_feeReceiver);
    }

    // =====================================================================
    // Private functions
    // =====================================================================

    /**
     * @dev Emits {Transfer} and {TransferShares} events where `from` is 0 address. Indicates mint events.
     */
    function _emitTransferAfterMintingShares(
        address _to,
        uint256 _sharesAmount
    ) internal {
        emit Transfer(address(0), _to, getPooledTokenByShares(_sharesAmount));
        emit TransferShares(address(0), _to, _sharesAmount);
    }

    function _getTotalPooledToken() internal view override returns (uint256) {
        return totalPooledToken;
    }

    function _updateDailyStatistic(
        uint256 _depositAmount,
        uint256 _withdrawAmount,
        uint256 _feeAmount,
        uint256 _pnlAmount,
        uint256 _yieldAmount
    ) internal {
        uint256 currentDateTimestamp = (block.timestamp / 86400) * 86400;
        if (dailyStatistic.timestamp != currentDateTimestamp) {
            dailyStatistic = DailyStatistic({
                timestamp: currentDateTimestamp,
                depositAmount: 0,
                withdrawAmount: 0,
                feeAmount: 0,
                pnlAmount: 0,
                yieldAmount: 0
            });
        }

        dailyStatistic.depositAmount += _depositAmount;
        dailyStatistic.withdrawAmount += _withdrawAmount;
        dailyStatistic.feeAmount += _feeAmount;
        dailyStatistic.pnlAmount += _pnlAmount;
        dailyStatistic.yieldAmount += _yieldAmount;

        emit DailyStatisticUpdated({
            timestamp: dailyStatistic.timestamp,
            depositAmount: dailyStatistic.depositAmount,
            withdrawAmount: dailyStatistic.withdrawAmount,
            feeAmount: dailyStatistic.feeAmount,
            pnlAmount: dailyStatistic.pnlAmount,
            yieldAmount: dailyStatistic.yieldAmount,
            totalShares: _getTotalShares(),
            totalPooledToken: totalPooledToken
        });
    }
}
