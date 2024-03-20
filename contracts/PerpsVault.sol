// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";
import {ILiquidityVault} from "./interfaces/ILiquidityVault.sol";
import {IPerpsVault} from "./interfaces/IPerpsVault.sol";
import {IPerpsVaultIntegrated} from "./interfaces/IPerpsVaultIntegrated.sol";
import {IPerpsMarketIntegrated} from "./interfaces/IPerpsMarketIntegrated.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pool} from "./core/Pool.sol";
import {Authorization} from "./securities/Authorization.sol";
import {Math} from "./utils/Math.sol";

contract PerpsVault is
    IPerpsVault,
    IPerpsVaultIntegrated,
    Authorization,
    ReentrancyGuard
{
    using Address for address;
    uint256 constant FACTOR = 10000;

    IERC20 public immutable USDB;
    ILiquidityVault public immutable LIQUIDITY_VAULT;

    address perpsMarket;
    address yieldReceiver;

    mapping(address => uint256) _balances;

    constructor(
        address _liquidityVault,
        address _usdb,
        address _blastPoints,
        address _owner,
        address _yieldReceiver
    ) {
        LIQUIDITY_VAULT = ILiquidityVault(_liquidityVault);
        USDB = IERC20(_usdb);
        IERC20Rebasing(_usdb).configure(IERC20Rebasing.YieldMode.CLAIMABLE);
        IBlastPoints(_blastPoints).configurePointsOperator(_owner);
        _setRole(_owner, CONTRACT_OWNER_ROLE, true);
        yieldReceiver = _yieldReceiver;
    }

    modifier onlyLiquidityVault() {
        require(
            address(LIQUIDITY_VAULT) == msg.sender,
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

    function claimAllYield() external {
        uint256 yield = IERC20Rebasing(address(USDB)).getClaimableAmount(
            address(this)
        );
        IERC20Rebasing(address(USDB)).claim(yieldReceiver, yield);
        emit YieldClaimed(yieldReceiver, yield);
    }

    function depositCollateral(
        address _account,
        uint256 _amount
    ) external nonReentrant onlyPerpsMarket {
        require(_amount > 0, "PerpsVault: Invalid amount");
        uint256 balanceBefore = _balanceUSDB();
        IPerpsMarketIntegrated(perpsMarket).depositCollateralCallback(_amount);
        require(
            balanceBefore + _amount <= _balanceUSDB(),
            "PerpsVault: Balance mismatch"
        );
        _balances[_account] += _amount;

        emit DepositCollateral(_account, _amount);
    }

    function withdrawCollateral(
        address _account,
        uint256 _amount
    ) public nonReentrant onlyPerpsMarket {
        require(_amount > 0, "PerpsVault: Invalid amount");
        require(
            balanceOf(_account) >= _amount,
            "PerpsVault: Not enough balance"
        );
        _balances[_account] -= _amount;
        USDB.transfer(perpsMarket, _amount);

        emit WithdrawCollateral(_account, _amount);
    }

    function withdrawAllCollateral(
        address _account
    ) external nonReentrant onlyPerpsMarket {
        uint256 amount = balanceOf(_account);
        withdrawCollateral(_account, amount);
    }

    function settleTrade(
        address _account,
        int256 _pnl,
        uint256 _fees
    ) external onlyPerpsMarket {
        int256 amount = _pnl - int256(_fees);
        if (amount > 0) {
            _balances[_account] += Math.abs(amount);
        } else if (amount < 0) {
            _balances[_account] -= Math.abs(amount);
        }
        LIQUIDITY_VAULT.settleTrade(_pnl, _fees);
    }

    function payCallback(uint256 amount) external onlyLiquidityVault {
        USDB.transfer(address(LIQUIDITY_VAULT), amount);
    }

    // =====================================================================
    // Getter
    // =====================================================================

    function balanceOf(address _account) public view returns (uint256) {
        return _balances[_account];
    }

    // =====================================================================
    // Setter
    // =====================================================================

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
}
