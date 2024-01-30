/*
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.18;

contract Authorization {
    mapping(bytes32 => mapping(address => bool)) roles;

    //Global
    bytes32 internal constant CONTRACT_OWNER_ROLE =
        keccak256("blaex.contract_owner_role");
    bytes32 internal constant OPERATOR_ROLE = keccak256("blaex.operator_role");

    //PV
    bytes32 internal constant PV_OPERATOR_ROLE =
        keccak256("blaex.PerpsVault.operator_role");

    //LV
    bytes32 internal constant DL_OPERATOR_ROLE =
        keccak256("blaex.LiquidityVault.operator_role");

    function setRole(
        address _user,
        bytes32 _role,
        bool active
    ) external auth(CONTRACT_OWNER_ROLE, msg.sender) {
        _setRole(_user, _role, active);
    }

    function isAuthorized(
        bytes32 _role,
        address _user
    ) public view returns (bool) {
        return roles[_role][_user];
    }

    modifier auth(bytes32 _role, address _user) {
        require(isAuthorized(_role, _user), "Unauthorized");
        _;
    }

    function _setRole(address _user, bytes32 _role, bool active) internal {
        roles[_role][_user] = active;
    }
}
