// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AdminPool
 * @dev Manages the 10% admin commission pool from trading cycle completions
 * 
 * Features:
 * - Receives 10% of profit commissions (USDT/USDC)
 * - Proportional distribution to stakeholders
 * - Multiple distribution strategies
 * - Emergency withdrawal
 * - Pausable operations
 * - Access control (admin, operator, auditor)
 * 
 * Commission Flow:
 * 1. User completes 200% trading cycle
 * 2. Backend calculates 20% commission
 * 3. Backend sends 10% to AdminPool (this contract)
 * 4. Backend sends 10% to SponsorPool contract
 * 5. AdminPool accumulates funds for periodic distribution
 * 
 * Distribution Strategies:
 * - Operations: 40% (platform costs, servers, APIs)
 * - Development: 30% (new features, maintenance)
 * - Marketing: 15% (user acquisition, campaigns)
 * - Reserve: 15% (emergency fund, future expansion)
 * 
 * @notice This contract holds real funds - security is critical
 * @custom:security-contact security@tradingdeco.com
 */
contract AdminPool is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           ROLES
    // =============================================================
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // =============================================================
    //                          STRUCTS
    // =============================================================
    
    /**
     * @dev Stakeholder information
     */
    struct Stakeholder {
        address wallet;
        uint256 sharePercentage; // In basis points (100 = 1%, 10000 = 100%)
        string category; // "operations", "development", "marketing", "reserve"
        bool active;
    }

    /**
     * @dev Distribution record
     */
    struct Distribution {
        uint256 timestamp;
        uint256 totalAmount;
        address token;
        string reason;
        uint256 stakeholdersCount;
    }

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice Supported tokens (USDT, USDC)
    mapping(address => bool) public supportedTokens;
    
    /// @notice List of stakeholders
    Stakeholder[] public stakeholders;
    
    /// @notice Distribution history
    Distribution[] public distributions;
    
    /// @notice Total commissions received per token
    mapping(address => uint256) public totalCommissionsReceived;
    
    /// @notice Total distributed per token
    mapping(address => uint256) public totalDistributed;
    
    /// @notice Minimum distribution amount (prevent gas waste)
    uint256 public minDistributionAmount;
    
    /// @notice Platform treasury (for operations wallet)
    address public treasury;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    event CommissionReceived(
        address indexed from,
        address indexed token,
        uint256 amount,
        string cycleId
    );
    
    event StakeholderAdded(
        uint256 indexed id,
        address indexed wallet,
        uint256 sharePercentage,
        string category
    );
    
    event StakeholderUpdated(
        uint256 indexed id,
        address indexed wallet,
        uint256 sharePercentage,
        bool active
    );
    
    event DistributionExecuted(
        uint256 indexed distributionId,
        address indexed token,
        uint256 totalAmount,
        uint256 stakeholdersCount,
        string reason
    );
    
    event EmergencyWithdraw(
        address indexed token,
        address indexed to,
        uint256 amount,
        string reason
    );

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize AdminPool contract
     * @param _treasury Platform treasury address
     * @param _admin Admin address with full control
     * @param _usdt USDT token address
     * @param _usdc USDC token address
     */
    constructor(
        address _treasury,
        address _admin,
        address _usdt,
        address _usdc
    ) {
        require(_treasury != address(0), "AdminPool: invalid treasury");
        require(_admin != address(0), "AdminPool: invalid admin");
        require(_usdt != address(0), "AdminPool: invalid USDT");
        require(_usdc != address(0), "AdminPool: invalid USDC");

        treasury = _treasury;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(AUDITOR_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);

        // Add supported tokens
        supportedTokens[_usdt] = true;
        supportedTokens[_usdc] = true;

        // Set minimum distribution (100 USDT to avoid gas waste)
        minDistributionAmount = 100 * 10**6; // USDT/USDC use 6 decimals

        // Initialize default stakeholders (40-30-15-15 split)
        _addStakeholder(_treasury, 4000, "operations"); // 40%
        _addStakeholder(_treasury, 3000, "development"); // 30%
        _addStakeholder(_treasury, 1500, "marketing"); // 15%
        _addStakeholder(_treasury, 1500, "reserve"); // 15%
    }

    // =============================================================
    //                     COMMISSION FUNCTIONS
    // =============================================================

    /**
     * @notice Receive commission from backend
     * @param token Token address (USDT or USDC)
     * @param amount Amount to deposit
     * @param cycleId Cycle identifier for tracking
     * 
     * @dev Called by backend when cycle completes
     * @dev Backend must approve this contract before calling
     */
    function receiveCommission(
        address token,
        uint256 amount,
        string memory cycleId
    ) external whenNotPaused nonReentrant onlyRole(OPERATOR_ROLE) {
        require(supportedTokens[token], "AdminPool: unsupported token");
        require(amount > 0, "AdminPool: zero amount");

        // Transfer tokens from sender
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update totals
        totalCommissionsReceived[token] += amount;

        emit CommissionReceived(msg.sender, token, amount, cycleId);
    }

    /**
     * @notice Distribute accumulated funds to stakeholders
     * @param token Token to distribute (USDT or USDC)
     * @param amount Amount to distribute (0 = all available)
     * @param reason Reason for distribution
     * 
     * @dev Distributes proportionally based on stakeholder shares
     * @dev Only callable by DISTRIBUTOR_ROLE
     */
    function distribute(
        address token,
        uint256 amount,
        string memory reason
    ) external whenNotPaused nonReentrant onlyRole(DISTRIBUTOR_ROLE) {
        require(supportedTokens[token], "AdminPool: unsupported token");

        // Get available balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "AdminPool: no balance");

        // Use all balance if amount is 0
        if (amount == 0 || amount > balance) {
            amount = balance;
        }

        require(amount >= minDistributionAmount, "AdminPool: below minimum");

        // Count active stakeholders
        uint256 activeCount = 0;
        uint256 totalShares = 0;
        
        for (uint256 i = 0; i < stakeholders.length; i++) {
            if (stakeholders[i].active) {
                activeCount++;
                totalShares += stakeholders[i].sharePercentage;
            }
        }

        require(activeCount > 0, "AdminPool: no active stakeholders");
        require(totalShares == 10000, "AdminPool: invalid total shares");

        // Distribute to each stakeholder
        uint256 distributed = 0;
        
        for (uint256 i = 0; i < stakeholders.length; i++) {
            if (stakeholders[i].active) {
                uint256 share = (amount * stakeholders[i].sharePercentage) / 10000;
                
                if (share > 0) {
                    IERC20(token).safeTransfer(stakeholders[i].wallet, share);
                    distributed += share;
                }
            }
        }

        // Update totals
        totalDistributed[token] += distributed;

        // Record distribution
        distributions.push(Distribution({
            timestamp: block.timestamp,
            totalAmount: distributed,
            token: token,
            reason: reason,
            stakeholdersCount: activeCount
        }));

        emit DistributionExecuted(
            distributions.length - 1,
            token,
            distributed,
            activeCount,
            reason
        );
    }

    // =============================================================
    //                   STAKEHOLDER MANAGEMENT
    // =============================================================

    /**
     * @notice Add new stakeholder
     * @param wallet Stakeholder wallet address
     * @param sharePercentage Share in basis points (100 = 1%)
     * @param category Category ("operations", "development", etc.)
     */
    function addStakeholder(
        address wallet,
        uint256 sharePercentage,
        string memory category
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addStakeholder(wallet, sharePercentage, category);
    }

    /**
     * @notice Update stakeholder information
     * @param id Stakeholder ID
     * @param wallet New wallet address
     * @param sharePercentage New share percentage
     * @param active Active status
     */
    function updateStakeholder(
        uint256 id,
        address wallet,
        uint256 sharePercentage,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(id < stakeholders.length, "AdminPool: invalid ID");
        require(wallet != address(0), "AdminPool: zero address");
        require(sharePercentage <= 10000, "AdminPool: invalid share");

        stakeholders[id].wallet = wallet;
        stakeholders[id].sharePercentage = sharePercentage;
        stakeholders[id].active = active;

        emit StakeholderUpdated(id, wallet, sharePercentage, active);
    }

    /**
     * @notice Get stakeholder information
     * @param id Stakeholder ID
     */
    function getStakeholder(uint256 id) 
        external 
        view 
        returns (
            address wallet,
            uint256 sharePercentage,
            string memory category,
            bool active
        ) 
    {
        require(id < stakeholders.length, "AdminPool: invalid ID");
        Stakeholder memory s = stakeholders[id];
        return (s.wallet, s.sharePercentage, s.category, s.active);
    }

    /**
     * @notice Get total number of stakeholders
     */
    function getStakeholdersCount() external view returns (uint256) {
        return stakeholders.length;
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get available balance for distribution
     * @param token Token address
     */
    function getAvailableBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get pool statistics
     * @param token Token address
     */
    function getPoolStats(address token) 
        external 
        view 
        returns (
            uint256 totalReceived,
            uint256 totalDist,
            uint256 available,
            uint256 distributionsCount
        ) 
    {
        return (
            totalCommissionsReceived[token],
            totalDistributed[token],
            IERC20(token).balanceOf(address(this)),
            distributions.length
        );
    }

    /**
     * @notice Get distribution by ID
     * @param id Distribution ID
     */
    function getDistribution(uint256 id) 
        external 
        view 
        returns (
            uint256 timestamp,
            uint256 totalAmount,
            address token,
            string memory reason,
            uint256 stakeholdersCount
        ) 
    {
        require(id < distributions.length, "AdminPool: invalid ID");
        Distribution memory d = distributions[id];
        return (d.timestamp, d.totalAmount, d.token, d.reason, d.stakeholdersCount);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set minimum distribution amount
     * @param amount New minimum amount
     */
    function setMinDistributionAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minDistributionAmount = amount;
    }

    /**
     * @notice Add supported token
     * @param token Token address to add
     */
    function addSupportedToken(address token) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(token != address(0), "AdminPool: zero address");
        supportedTokens[token] = true;
    }

    /**
     * @notice Remove supported token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        supportedTokens[token] = false;
    }

    /**
     * @notice Emergency withdraw all funds
     * @param token Token to withdraw
     * @param to Destination address
     * @param reason Reason for emergency withdraw
     * 
     * @dev Use only in critical situations
     */
    function emergencyWithdraw(
        address token,
        address to,
        string memory reason
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(to != address(0), "AdminPool: zero address");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "AdminPool: no balance");

        IERC20(token).safeTransfer(to, balance);

        emit EmergencyWithdraw(token, to, balance, reason);
    }

    /**
     * @notice Pause contract operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    function _addStakeholder(
        address wallet,
        uint256 sharePercentage,
        string memory category
    ) internal {
        require(wallet != address(0), "AdminPool: zero address");
        require(sharePercentage <= 10000, "AdminPool: invalid share");

        stakeholders.push(Stakeholder({
            wallet: wallet,
            sharePercentage: sharePercentage,
            category: category,
            active: true
        }));

        emit StakeholderAdded(
            stakeholders.length - 1,
            wallet,
            sharePercentage,
            category
        );
    }
}
