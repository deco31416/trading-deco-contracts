// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AHTToken
 * @dev AHT (Algo Hybrid Trading) Token - ERC20 token for Trading Deco platform
 * 
 * Features:
 * - Fixed supply: 1,000,000 AHT tokens
 * - 18 decimals (standard)
 * - Burnable (users can burn their tokens)
 * - Pausable (emergency stop)
 * - Access control (admin, minter roles)
 * - Initial distribution to platform treasury
 * 
 * Token Utility:
 * - Access to Premium Panel (300+ AHT required)
 * - Governance rights (future)
 * - Staking rewards (future)
 * - Fee discounts (future)
 * 
 * Distribution Plan:
 * - 40% (400k) - Platform Treasury
 * - 20% (200k) - Team & Advisors (vested)
 * - 20% (200k) - Community Rewards
 * - 10% (100k) - Liquidity Pool (DEX)
 * - 10% (100k) - Strategic Partners
 * 
 * @notice This contract follows OpenZeppelin best practices
 * @custom:security-contact security@tradingdeco.com
 */
contract AHTToken is 
    ERC20, 
    ERC20Burnable, 
    ERC20Pausable, 
    AccessControl, 
    ReentrancyGuard 
{
    // =============================================================
    //                           ROLES
    // =============================================================
    
    /// @notice Role for pausing/unpausing token transfers
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Role for minting new tokens (only for vesting unlocks)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // =============================================================
    //                         CONSTANTS
    // =============================================================
    
    /// @notice Maximum supply of AHT tokens (1 million)
    uint256 public constant MAX_SUPPLY = 1_000_000 * 10**18;
    
    /// @notice Premium panel requirement (300 AHT)
    uint256 public constant PREMIUM_THRESHOLD = 300 * 10**18;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    /// @notice Emitted when tokens are minted for vesting unlock
    event TokensMinted(address indexed to, uint256 amount, string reason);
    
    /// @notice Emitted when premium status is checked
    event PremiumStatusChecked(address indexed account, bool isPremium, uint256 balance);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize AHT Token with fixed supply
     * @param treasury Address to receive initial token supply
     * @param admin Address with admin privileges
     * 
     * @dev Initial supply is minted to treasury for distribution
     */
    constructor(
        address treasury,
        address admin
    ) ERC20("Algo Hybrid Trading Token", "AHT") {
        require(treasury != address(0), "AHT: treasury is zero address");
        require(admin != address(0), "AHT: admin is zero address");

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);

        // Mint initial supply to treasury
        _mint(treasury, MAX_SUPPLY);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Pause all token transfers
     * @dev Only callable by PAUSER_ROLE
     * 
     * Emergency use only:
     * - Security breach detected
     * - Critical bug found
     * - Regulatory requirement
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     * @dev Only callable by PAUSER_ROLE
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Mint new tokens (only for vesting unlocks)
     * @param to Address to receive minted tokens
     * @param amount Amount of tokens to mint
     * @param reason Reason for minting (e.g., "Team vesting unlock Q1 2025")
     * 
     * @dev This function is restricted and should only be used for:
     * - Team vesting schedule unlocks
     * - Advisor vesting unlocks
     * - Strategic partner distributions
     * 
     * NOTE: Total supply cannot exceed MAX_SUPPLY
     */
    function mint(
        address to,
        uint256 amount,
        string memory reason
    ) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "AHT: mint to zero address");
        require(amount > 0, "AHT: mint amount is zero");
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "AHT: exceeds max supply"
        );

        _mint(to, amount);
        emit TokensMinted(to, amount, reason);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Check if an account has premium status (300+ AHT)
     * @param account Address to check
     * @return bool True if account has >= 300 AHT
     * 
     * @dev Used by backend to verify premium panel access
     */
    function hasPremiumStatus(address account) external view returns (bool) {
        return balanceOf(account) >= PREMIUM_THRESHOLD;
    }

    /**
     * @notice Check if an account can afford premium panel
     * @param account Address to check
     * @return hasAccess True if account has premium status
     * @return currentBalance Current AHT balance
     * @return required Required AHT amount (300)
     * @return shortfall Amount needed to reach premium (0 if already premium)
     * 
     * @dev Provides detailed premium status information
     */
    function checkPremiumStatus(address account) 
        external 
        view 
        returns (
            bool hasAccess,
            uint256 currentBalance,
            uint256 required,
            uint256 shortfall
        ) 
    {
        currentBalance = balanceOf(account);
        required = PREMIUM_THRESHOLD;
        hasAccess = currentBalance >= required;
        shortfall = hasAccess ? 0 : required - currentBalance;
    }

    /**
     * @notice Get token information
     * @return name Token name
     * @return symbol Token symbol
     * @return decimals Token decimals
     * @return supply Total supply
     * @return maxSupply Maximum possible supply
     */
    function getTokenInfo() 
        external 
        view 
        returns (
            string memory name,
            string memory symbol,
            uint8 decimals,
            uint256 supply,
            uint256 maxSupply
        ) 
    {
        return (
            name(),
            symbol(),
            decimals(),
            totalSupply(),
            MAX_SUPPLY
        );
    }

    // =============================================================
    //                    INTERNAL OVERRIDES
    // =============================================================

    /**
     * @dev Override required by Solidity for multiple inheritance
     * 
     * Execution order:
     * 1. ERC20Pausable - Check if transfers are paused
     * 2. ERC20 - Execute transfer logic
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, amount);
    }

    // =============================================================
    //                         UTILITIES
    // =============================================================

    /**
     * @notice Recover ERC20 tokens accidentally sent to contract
     * @param token Address of ERC20 token to recover
     * @param to Address to send recovered tokens
     * @param amount Amount to recover
     * 
     * @dev Only callable by admin
     * @dev Cannot recover AHT tokens (use burn instead)
     */
    function recoverERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(token != address(this), "AHT: cannot recover AHT tokens");
        require(to != address(0), "AHT: recover to zero address");
        require(amount > 0, "AHT: recover amount is zero");

        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Check if contract supports interface
     * @param interfaceId Interface identifier
     * @return bool True if interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
