// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";
import {ILiquidityVault} from "./interfaces/ILiquidityVault.sol";
import {IPerpsVaultCallback} from "./interfaces/IPerpsVaultCallback.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PoolERC20} from "./core/PoolERC20.sol";
import {Authorization} from "./securities/Authorization.sol";
import {Math} from "./utils/Math.sol";

contract LiquidityVault is
    ILiquidityVault,
    PoolERC20,
    Authorization,
    ReentrancyGuard
{
    using Address for address;
    uint256 constant FACTOR = 10000;

    DailyStatistic dailyStatistic;

    address perpsVault;
    address feeReceiver;
    uint256 fee;

    IERC20 public immutable USDB;

    constructor(
        address _usdb,
        address _blastPoints,
        address _owner,
        address _feeReceiver
    ) PoolERC20("Blaex Liquidity Index", "BLI") {
        USDB = IERC20(_usdb);
        IERC20Rebasing(_usdb).configure(IERC20Rebasing.YieldMode.AUTOMATIC);
        IBlastPoints(_blastPoints).configurePointsOperator(_owner);
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
        feeReceiver = _feeReceiver;
    }

    modifier onlyPerpsVault() {
        require(perpsVault == msg.sender, "LiquidityVault: Only PerpsVault");
        _;
    }

    // =====================================================================
    // Main functions
    // =====================================================================

    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "LiquidityVault: Invalid amount");
        uint256 feeAmount = (_amount * fee) / FACTOR;
        uint256 depositAmount = _amount - feeAmount;

        uint256 sharesAmount = getSharesByPooledToken(depositAmount);
        if (sharesAmount == 0) {
            sharesAmount = depositAmount;
        }

        USDB.transferFrom(msg.sender, address(this), _amount);
        USDB.transfer(feeReceiver, feeAmount);
        _mintShares(msg.sender, sharesAmount);

        emit Deposit(msg.sender, _amount, sharesAmount);
        emit FeeCharged(msg.sender, feeReceiver, feeAmount);

        _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    }

    function withdraw(uint256 _sharesAmount) external nonReentrant {
        require(_sharesAmount > 0, "LiquidityVault: Invalid amount");
        require(
            balanceOf(msg.sender) >= _sharesAmount,
            "LiquidityVault: Not enough balance"
        );

        uint256 amount = getPooledTokenByShares(_sharesAmount);

        uint256 feeAmount = (amount * fee) / FACTOR;
        uint256 withdrawAmount = amount - feeAmount;
        //Burn

        _burnShares(msg.sender, _sharesAmount);
        USDB.transfer(msg.sender, withdrawAmount);
        USDB.transfer(feeReceiver, feeAmount);

        emit Withdraw(msg.sender, _sharesAmount, amount);
        emit FeeCharged(msg.sender, feeReceiver, feeAmount);
    }

    function settleTrade(
        int256 _pnl,
        uint256 _fees
    ) external nonReentrant onlyPerpsVault {
        int256 delta = _pnl - int256(_fees);

        if (delta > 0) {
            USDB.transfer(perpsVault, Math.abs(delta));
        } else if (delta < 0) {
            uint256 balanceBefore = _balanceUSDB();
            IPerpsVaultCallback(msg.sender).payCallback(Math.abs(delta));
            require(
                balanceBefore - Math.abs(delta) <= _balanceUSDB(),
                "LiquidityVault: Balance mismatch"
            );
        }
        // counter party with trader
        _updateDailyStatistic(_pnl * -1, _fees);

        emit TradeSettled(_pnl, _fees);
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
        emit FeeUpdated(_fee);
    }

    function setFeeReceiver(
        address _feeReceiver
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    function setPerpsVault(
        address _perpsVault
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        // TODO: enable again
        // require(perpsVault == address(0), "LiquidityVault: Already set");
        perpsVault = _perpsVault;
        emit PerpsVaultSetted(_perpsVault);
    }

    // =====================================================================
    // Private functions
    // =====================================================================

    function _balanceUSDB() private view returns (uint256) {
        (bool success, bytes memory data) = address(USDB).staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

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

    function _updateDailyStatistic(int256 _pnl, uint256 _yield) internal {
        uint256 currentDateTimestamp = (block.timestamp / 86400) * 86400;
        if (dailyStatistic.timestamp != currentDateTimestamp) {
            dailyStatistic = DailyStatistic({
                timestamp: currentDateTimestamp,
                pnl: 0,
                yield: 0
            });
        }

        dailyStatistic.pnl += _pnl;
        dailyStatistic.yield += _yield;

        emit DailyStatisticUpdated({
            timestamp: dailyStatistic.timestamp,
            pnl: dailyStatistic.pnl,
            yield: dailyStatistic.yield,
            totalShares: _getTotalShares(),
            totalPooledToken: _getTotalPooledToken()
        });
    }
}
