
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * TreasuryRouter
 * - Custodia USDC (u otro ERC20) con roles: ADMIN, OPERATOR, AUDITOR.
 * - Rutas de retiro hacia "venues" (dYdX, Hyperliquid) o wallets específicas.
 * - Anti reentrada, pausas, y emergencia: withdrawAll por ADMIN.
 * - Logs de depósitos/retiros, y límites por rol (extensible).
 */
contract TreasuryRouter is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    IERC20 public immutable token; // USDC
    address public treasury;       // main treasury account (may be a multisig)

    mapping(bytes32 => address) public venueAddress; // e.g., keccak256("dydx:base"), keccak256("hyperliquid:arbitrum")
    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed to, uint256 amount, string venue, string network);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event VenueSet(string venue, string network, address to);

    constructor(address _token, address _treasury, address admin) {
        token = IERC20(_token);
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(AUDITOR_ROLE, admin);
    }

    function setVenueAddress(string memory venue, string memory network, address to) external onlyRole(ADMIN_ROLE) {
        bytes32 key = keccak256(abi.encodePacked(venue, ":", network));
        venueAddress[key] = to;
        emit VenueSet(venue, network, to);
    }

    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    function withdrawToVenue(string memory venue, string memory network, uint256 amount) external whenNotPaused nonReentrant onlyRole(OPERATOR_ROLE) {
        bytes32 key = keccak256(abi.encodePacked(venue, ":", network));
        address to = venueAddress[key];
        require(to != address(0), "venue not set");
        token.safeTransfer(to, amount);
        emit Withdraw(to, amount, venue, network);
    }

    function withdrawTo(address to, uint256 amount) external whenNotPaused nonReentrant onlyRole(ADMIN_ROLE) {
        token.safeTransfer(to, amount);
        emit Withdraw(to, amount, "direct", "n/a");
    }

    function emergencyWithdrawAll(address to) external nonReentrant onlyRole(ADMIN_ROLE) {
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(to, bal);
        emit EmergencyWithdraw(to, bal);
    }

    function pause() external onlyRole(ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(ADMIN_ROLE) { _unpause(); }
}
