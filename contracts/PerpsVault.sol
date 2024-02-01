// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidityVault} from "./interfaces/ILiquidityVault.sol";
import {IPerpsVault} from "./interfaces/IPerpsVault.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";
import {IPerpsVaultCallback} from "./interfaces/IPerpsVaultCallback.sol";
import {IPerpsMarketCallback} from "./interfaces/IPerpsMarketCallback.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pool} from "./core/Pool.sol";
import {Authorization} from "./securities/Authorization.sol";

contract PerpsVault is
    IPerpsVault,
    IPerpsVaultCallback,
    Pool,
    Authorization,
    ReentrancyGuard
{
    using Address for address;
    uint256 constant FACTOR = 10000;

    ILiquidityVault liquidityVault;
    address perpsMarket;

    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);

    constructor(address _owner) Pool() {
        IERC20Rebasing(address(USDB)).configure(
            IERC20Rebasing.YieldMode.AUTOMATIC
        );
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
    }

    modifier onlyLiquidityVault() {
        require(
            address(liquidityVault) == msg.sender,
            "PerpsVault: Only LiquidityVault"
        );
        _;
    }

    modifier onlyPerpsMarket() {
        require(perpsMarket == msg.sender, "PerpsVault: Only PerpsMarket");
        _;
    }

    // =====================================================================
    // Main functions
    // =====================================================================

    function depositCollateral(
        address _account,
        uint256 _amount
    ) external nonReentrant onlyPerpsMarket {
        require(_amount > 0, "PerpsVault: Invalid amount");
        uint256 balanceBefore = _balanceUSDB();
        IPerpsMarketCallback(perpsMarket).depositCollateralCallback(_amount);
        require(
            balanceBefore + _amount <= _balanceUSDB(),
            "PerpsVault: Balance mismatch"
        );

        uint256 sharesAmount = getSharesByPooledToken(_amount);
        if (sharesAmount == 0) {
            sharesAmount = _amount;
        }

        _mintShares(_account, sharesAmount);

        emit DepositCollateral(_account, _amount);
    }

    function withdrawCollateral(
        address _account,
        uint256 _amount
    ) external nonReentrant onlyPerpsMarket {
        require(_amount > 0, "PerpsVault: Invalid amount");
        require(
            balanceOf(_account) >= _amount,
            "PerpsVault: Not enough balance"
        );

        USDB.transfer(perpsMarket, _amount);

        //Burn
        uint256 sharesAmount = getSharesByPooledToken(_amount);
        _burnShares(_account, sharesAmount);

        emit WithdrawCollateral(_account, _amount);
    }

    function withdrawAllCollateral(
        address _account
    ) external nonReentrant onlyPerpsMarket {
        uint256 amount = balanceOf(_account);

        USDB.transfer(perpsMarket, amount);

        //Burn
        uint256 sharesAmount = getSharesByPooledToken(amount);
        _burnShares(_account, sharesAmount);

        emit WithdrawCollateral(_account, amount);
    }

    function settleTrade(
        address _account,
        int256 _pnl,
        uint256 _fees
    ) external onlyPerpsMarket {
        uint256 amount = _abs(_pnl - int256(_fees));
        uint256 sharesAmount = getSharesByPooledToken(amount);
        if (sharesAmount > 0) {
            if (sharesAmount == 0) {
                sharesAmount = amount;
            }
            _mintShares(_account, sharesAmount);
        } else if (sharesAmount < 0) {
            _burnShares(_account, sharesAmount);
        }
        liquidityVault.settleTrade(_pnl, _fees);
    }

    function payCallback(uint256 amount) external onlyLiquidityVault {
        USDB.transfer(address(liquidityVault), amount);
    }

    // =====================================================================
    // Getter
    // =====================================================================

    /**
     * @return the amount of tokens owned by the `_account`.
     *
     * @dev Balances are dynamic and equal the `_account`'s share in the amount of the
     * total Token controlled by the protocol. See `sharesOf`.
     */
    function balanceOf(address _account) public view returns (uint256) {
        return getPooledTokenByShares(_sharesOf(_account));
    }

    // =====================================================================
    // Setter
    // =====================================================================

    function setLiquidityVault(
        address _liquidityVault
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        // TODO: enable again
        // require(
        //     address(liquidityVault) == address(0),
        //     "PerpsVault: Already set"
        // );
        liquidityVault = ILiquidityVault(_liquidityVault);
        emit LiquidityVaultSetted(_liquidityVault);
    }

    function setPerpsMarket(
        address _perpsMarket
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        // TODO: enable again
        // require(perpsMarket == address(0), "PerpsVault: Already set");
        perpsMarket = _perpsMarket;
        emit PerpsMarketSetted(_perpsMarket);
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

    function _getTotalPooledToken() internal view override returns (uint256) {
        return USDB.balanceOf(address(this));
    }
}