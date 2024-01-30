// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBLI} from "./interfaces/IBLI.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PoolERC20} from "./core/PoolERC20.sol";
import {Authorization} from "./securities/Authorization.sol";

contract BLI is IBLI, PoolERC20, Authorization, ReentrancyGuard {
    using Address for address;
    uint256 constant FACTOR = 10000;

    DailyStatistic dailyStatistic;

    address feeReceiver;
    uint256 fee;

    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);

    constructor(
        address _owner,
        address _feeReceiver
    ) PoolERC20("Blaex Liquidity Index", "BLI") {
        IERC20Rebasing(address(USDB)).configure(
            IERC20Rebasing.YieldMode.AUTOMATIC
        );
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
        feeReceiver = _feeReceiver;
        fee = 0;
    }

    // =====================================================================
    // Main functions
    // =====================================================================
    /**
     * @dev Process user deposit, mints liquid tokens and increase the pool buffer
     */
    function deposit(uint256 _amount) external nonReentrant {
        uint256 feeAmount = (_amount * fee) / FACTOR;
        uint256 depositAmount = _amount - feeAmount;
        USDB.transferFrom(msg.sender, address(this), _amount);
        USDB.transfer(feeReceiver, feeAmount);

        uint256 sharesAmount = getSharesByPooledToken(depositAmount);
        if (sharesAmount == 0) {
            sharesAmount = depositAmount;
        }

        _mintShares(msg.sender, sharesAmount);

        emit Deposit(msg.sender, _amount);
        emit ChargeFee(msg.sender, feeReceiver, feeAmount);

        _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    }

    /**
     * @dev Process withdraw, burn stRon and withdraw from delegate batch the corresponding amount of Token to the user
     *
     * Emits `Withdraw` event
     */
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= _amount, "Not enough balance");

        uint256 feeAmount = (_amount * fee) / FACTOR;
        uint256 withdrawAmount = _amount - feeAmount;

        USDB.transfer(msg.sender, withdrawAmount);
        USDB.transfer(feeReceiver, feeAmount);

        //Burn
        uint256 sharesAmount = getSharesByPooledToken(_amount);
        _burnShares(msg.sender, sharesAmount);

        emit Withdraw(msg.sender, _amount);
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
        return USDB.balanceOf(address(this));
    }

    function _updateDailyStatistic(
        int256 _pnl,
        uint256 _realYield,
        uint256 _nativeYield
    ) internal {
        uint256 currentDateTimestamp = (block.timestamp / 86400) * 86400;
        if (dailyStatistic.timestamp != currentDateTimestamp) {
            dailyStatistic = DailyStatistic({
                timestamp: currentDateTimestamp,
                pnl: 0,
                realYield: 0,
                nativeYield: 0
            });
        }

        dailyStatistic.pnl += _pnl;
        dailyStatistic.realYield += _realYield;
        dailyStatistic.nativeYield += _nativeYield;

        emit DailyStatisticUpdated({
            timestamp: dailyStatistic.timestamp,
            pnl: dailyStatistic.pnl,
            realYield: dailyStatistic.realYield,
            nativeYield: dailyStatistic.nativeYield,
            totalShares: _getTotalShares(),
            totalPooledToken: _getTotalPooledToken()
        });
    }
}
