// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpsVault} from "../interfaces/IPerpsVault.sol";

contract MockPerpsMarket {
    IERC20 public constant USDB =
        IERC20(0x4200000000000000000000000000000000000022);

    IPerpsVault perpsVault;

    modifier onlyPerpsVault() {
        require(
            address(perpsVault) == msg.sender,
            "PerpsMarket: Only PerpsVault"
        );
        _;
    }

    constructor(address _perpsVault) {
        perpsVault = IPerpsVault(_perpsVault);
    }

    function depositCollateralCallback(
        uint256 _amount
    ) external onlyPerpsVault {
        USDB.transfer(address(perpsVault), _amount);
    }

    function depositCollateral(address _account, uint256 _amount) external {
        USDB.transferFrom(msg.sender, address(this), _amount);
        perpsVault.depositCollateral(_account, _amount);
    }

    function withdrawCollateral(address _account, uint256 _amount) external {
        perpsVault.withdrawCollateral(_account, _amount);
        USDB.transfer(_account, _amount);
    }

    function withdrawAllCollateral(address _account) external {
        perpsVault.withdrawAllCollateral(_account);
    }

    function settleTrade(
        address _account,
        int256 _pnl,
        uint256 _fees
    ) external {
        perpsVault.settleTrade(_account, _pnl, _fees);
    }
}
