// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidityVault} from "./interfaces/ILiquidityVault.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";
import {IPerpsVaultCallback} from "./interfaces/IPerpsVaultCallback.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PoolERC20} from "./core/PoolERC20.sol";
import {Authorization} from "./securities/Authorization.sol";

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
        USDB.transferFrom(msg.sender, address(this), _amount);
        USDB.transfer(feeReceiver, feeAmount);

        uint256 sharesAmount = getSharesByPooledToken(depositAmount);
        if (sharesAmount == 0) {
            sharesAmount = depositAmount;
        }

        _mintShares(msg.sender, sharesAmount);

        emit Deposit(msg.sender, _amount);
        emit FeeCharged(msg.sender, feeReceiver, feeAmount);

        _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "LiquidityVault: Invalid amount");
        require(
            balanceOf(msg.sender) >= _amount,
            "LiquidityVault: Not enough balance"
        );

        uint256 feeAmount = (_amount * fee) / FACTOR;
        uint256 withdrawAmount = _amount - feeAmount;

        USDB.transfer(msg.sender, withdrawAmount);
        USDB.transfer(feeReceiver, feeAmount);

        //Burn
        uint256 sharesAmount = getSharesByPooledToken(_amount);
        _burnShares(msg.sender, sharesAmount);

        emit Withdraw(msg.sender, _amount);
        emit FeeCharged(msg.sender, feeReceiver, feeAmount);
    }

    function settleTrade(
        int256 _pnl,
        uint256 _fees
    ) external nonReentrant onlyPerpsVault {
        int256 delta = _pnl - int256(_fees);

        if (delta > 0) {
            USDB.transfer(perpsVault, _abs(delta));
        } else if (delta < 0) {
            uint256 balanceBefore = _balanceUSDB();
            IPerpsVaultCallback(msg.sender).payCallback(_abs(delta));
            require(
                balanceBefore - _abs(delta) <= _balanceUSDB(),
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

    function _abs(int256 x) internal pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
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
