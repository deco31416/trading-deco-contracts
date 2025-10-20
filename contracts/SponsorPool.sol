// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SponsorPool
 * @dev Manages the 10% sponsor commission pool from trading cycle completions
 * 
 * Features:
 * - Receives 10% of profit commissions (USDT/USDC)
 * - Individual claims by sponsors
 * - Vesting schedules (optional)
 * - Claim history tracking
 * - Emergency withdrawal
 * - Pausable operations
 * - Access control (admin, operator, auditor)
 * 
 * Commission Flow:
 * 1. Referred user completes 200% trading cycle
 * 2. Backend calculates 20% commission
 * 3. Backend sends 10% to AdminPool contract
 * 4. Backend sends 10% to SponsorPool (this contract)
 * 5. Backend records earning in SponsorEarning DB
 * 6. Sponsor claims their share via contract
 * 
 * Claim Process:
 * 1. Sponsor initiates claim via backend API
 * 2. Backend verifies ownership and pending amount
 * 3. Backend calls recordEarning() to register on-chain
 * 4. Sponsor calls claimEarning() to receive tokens
 * 5. Contract transfers tokens to sponsor wallet
 * 
 * @notice This contract holds real funds - security is critical
 * @custom:security-contact security@tradingdeco.com
 */
contract SponsorPool is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           ROLES
    // =============================================================
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // =============================================================
    //                          STRUCTS
    // =============================================================
    
    /**
     * @dev Earning record for a sponsor
     */
    struct Earning {
        address sponsor;
        address token;
        uint256 amount;
        uint256 timestamp;
        string earningId; // Links to backend SponsorEarning record
        string cycleId; // Original trading cycle ID
        bool claimed;
        uint256 claimedAt;
        uint256 vestingEnd; // Optional vesting (0 = immediate)
    }

    /**
     * @dev Sponsor statistics
     */
    struct SponsorStats {
        uint256 totalEarned;
        uint256 totalClaimed;
        uint256 pendingAmount;
        uint256 earningsCount;
        uint256 claimsCount;
    }

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice Supported tokens (USDT, USDC)
    mapping(address => bool) public supportedTokens;
    
    /// @notice All earnings records
    Earning[] public earnings;
    
    /// @notice Sponsor address => earning IDs
    mapping(address => uint256[]) public sponsorEarnings;
    
    /// @notice Backend earningId => contract earning ID
    mapping(string => uint256) public earningIdToIndex;
    
    /// @notice Sponsor statistics
    mapping(address => SponsorStats) public sponsorStats;
    
    /// @notice Total commissions received per token
    mapping(address => uint256) public totalCommissionsReceived;
    
    /// @notice Total claimed per token
    mapping(address => uint256) public totalClaimed;
    
    /// @notice Minimum claim amount (prevent gas waste)
    uint256 public minClaimAmount;
    
    /// @notice Default vesting period (0 = no vesting)
    uint256 public defaultVestingPeriod;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    event CommissionReceived(
        address indexed from,
        address indexed token,
        uint256 amount,
        string cycleId
    );
    
    event EarningRecorded(
        uint256 indexed earningIndex,
        address indexed sponsor,
        address indexed token,
        uint256 amount,
        string earningId,
        string cycleId,
        uint256 vestingEnd
    );
    
    event EarningClaimed(
        uint256 indexed earningIndex,
        address indexed sponsor,
        address indexed token,
        uint256 amount,
        string earningId
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
     * @notice Initialize SponsorPool contract
     * @param _admin Admin address with full control
     * @param _usdt USDT token address
     * @param _usdc USDC token address
     */
    constructor(
        address _admin,
        address _usdt,
        address _usdc
    ) {
        require(_admin != address(0), "SponsorPool: invalid admin");
        require(_usdt != address(0), "SponsorPool: invalid USDT");
        require(_usdc != address(0), "SponsorPool: invalid USDC");

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(AUDITOR_ROLE, _admin);

        // Add supported tokens
        supportedTokens[_usdt] = true;
        supportedTokens[_usdc] = true;

        // Set minimum claim (10 USDT to avoid gas waste)
        minClaimAmount = 10 * 10**6; // USDT/USDC use 6 decimals

        // No vesting by default
        defaultVestingPeriod = 0;
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
        require(supportedTokens[token], "SponsorPool: unsupported token");
        require(amount > 0, "SponsorPool: zero amount");

        // Transfer tokens from sender
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update totals
        totalCommissionsReceived[token] += amount;

        emit CommissionReceived(msg.sender, token, amount, cycleId);
    }

    // =============================================================
    //                      EARNING FUNCTIONS
    // =============================================================

    /**
     * @notice Record new earning for sponsor
     * @param sponsor Sponsor wallet address
     * @param token Token address (USDT or USDC)
     * @param amount Earning amount
     * @param earningId Backend earning ID (from SponsorEarning DB)
     * @param cycleId Original trading cycle ID
     * @param vestingPeriod Vesting period in seconds (0 = immediate)
     * 
     * @dev Called by backend OPERATOR_ROLE
     * @dev Backend must ensure earning is not already recorded
     */
    function recordEarning(
        address sponsor,
        address token,
        uint256 amount,
        string memory earningId,
        string memory cycleId,
        uint256 vestingPeriod
    ) external whenNotPaused nonReentrant onlyRole(OPERATOR_ROLE) {
        require(sponsor != address(0), "SponsorPool: zero address");
        require(supportedTokens[token], "SponsorPool: unsupported token");
        require(amount > 0, "SponsorPool: zero amount");
        require(bytes(earningId).length > 0, "SponsorPool: empty earningId");
        require(earningIdToIndex[earningId] == 0, "SponsorPool: duplicate earning");

        // Calculate vesting end
        uint256 vestingEnd = vestingPeriod > 0 
            ? block.timestamp + vestingPeriod 
            : 0;

        // Create earning record
        earnings.push(Earning({
            sponsor: sponsor,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            earningId: earningId,
            cycleId: cycleId,
            claimed: false,
            claimedAt: 0,
            vestingEnd: vestingEnd
        }));

        uint256 earningIndex = earnings.length - 1;

        // Map earningId to index
        earningIdToIndex[earningId] = earningIndex + 1; // +1 to differentiate from 0

        // Add to sponsor's earnings list
        sponsorEarnings[sponsor].push(earningIndex);

        // Update sponsor stats
        sponsorStats[sponsor].totalEarned += amount;
        sponsorStats[sponsor].pendingAmount += amount;
        sponsorStats[sponsor].earningsCount++;

        emit EarningRecorded(
            earningIndex,
            sponsor,
            token,
            amount,
            earningId,
            cycleId,
            vestingEnd
        );
    }

    /**
     * @notice Claim earning by index
     * @param earningIndex Index of earning to claim
     * 
     * @dev Anyone can call but tokens go to earning owner
     * @dev Checks vesting period and ownership
     */
    function claimEarning(uint256 earningIndex) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(earningIndex < earnings.length, "SponsorPool: invalid index");
        
        Earning storage earning = earnings[earningIndex];
        
        require(!earning.claimed, "SponsorPool: already claimed");
        require(earning.sponsor == msg.sender, "SponsorPool: not owner");
        require(earning.amount >= minClaimAmount, "SponsorPool: below minimum");
        
        // Check vesting
        if (earning.vestingEnd > 0) {
            require(block.timestamp >= earning.vestingEnd, "SponsorPool: vesting not ended");
        }

        // Check contract balance
        uint256 balance = IERC20(earning.token).balanceOf(address(this));
        require(balance >= earning.amount, "SponsorPool: insufficient balance");

        // Mark as claimed
        earning.claimed = true;
        earning.claimedAt = block.timestamp;

        // Update stats
        sponsorStats[earning.sponsor].totalClaimed += earning.amount;
        sponsorStats[earning.sponsor].pendingAmount -= earning.amount;
        sponsorStats[earning.sponsor].claimsCount++;
        totalClaimed[earning.token] += earning.amount;

        // Transfer tokens
        IERC20(earning.token).safeTransfer(earning.sponsor, earning.amount);

        emit EarningClaimed(
            earningIndex,
            earning.sponsor,
            earning.token,
            earning.amount,
            earning.earningId
        );
    }

    /**
     * @notice Claim earning by backend earningId
     * @param earningId Backend earning ID
     */
    function claimEarningById(string memory earningId) external {
        uint256 index = earningIdToIndex[earningId];
        require(index > 0, "SponsorPool: earning not found");
        claimEarning(index - 1); // -1 because we added 1 when storing
    }

    /**
     * @notice Batch claim multiple earnings
     * @param earningIndexes Array of earning indexes to claim
     * 
     * @dev Gas-efficient batch claiming
     */
    function claimMultipleEarnings(uint256[] memory earningIndexes) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(earningIndexes.length > 0, "SponsorPool: empty array");
        require(earningIndexes.length <= 50, "SponsorPool: too many claims");

        for (uint256 i = 0; i < earningIndexes.length; i++) {
            uint256 earningIndex = earningIndexes[i];
            require(earningIndex < earnings.length, "SponsorPool: invalid index");
            
            Earning storage earning = earnings[earningIndex];
            
            // Skip if already claimed or not owner
            if (earning.claimed || earning.sponsor != msg.sender) {
                continue;
            }

            // Skip if vesting not ended
            if (earning.vestingEnd > 0 && block.timestamp < earning.vestingEnd) {
                continue;
            }

            // Skip if below minimum
            if (earning.amount < minClaimAmount) {
                continue;
            }

            // Check contract balance
            uint256 balance = IERC20(earning.token).balanceOf(address(this));
            if (balance < earning.amount) {
                continue;
            }

            // Mark as claimed
            earning.claimed = true;
            earning.claimedAt = block.timestamp;

            // Update stats
            sponsorStats[earning.sponsor].totalClaimed += earning.amount;
            sponsorStats[earning.sponsor].pendingAmount -= earning.amount;
            sponsorStats[earning.sponsor].claimsCount++;
            totalClaimed[earning.token] += earning.amount;

            // Transfer tokens
            IERC20(earning.token).safeTransfer(earning.sponsor, earning.amount);

            emit EarningClaimed(
                earningIndex,
                earning.sponsor,
                earning.token,
                earning.amount,
                earning.earningId
            );
        }
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get earning by index
     * @param earningIndex Earning index
     */
    function getEarning(uint256 earningIndex) 
        external 
        view 
        returns (
            address sponsor,
            address token,
            uint256 amount,
            uint256 timestamp,
            string memory earningId,
            string memory cycleId,
            bool claimed,
            uint256 claimedAt,
            uint256 vestingEnd
        ) 
    {
        require(earningIndex < earnings.length, "SponsorPool: invalid index");
        Earning memory e = earnings[earningIndex];
        return (
            e.sponsor,
            e.token,
            e.amount,
            e.timestamp,
            e.earningId,
            e.cycleId,
            e.claimed,
            e.claimedAt,
            e.vestingEnd
        );
    }

    /**
     * @notice Get earning by backend earningId
     * @param earningId Backend earning ID
     */
    function getEarningById(string memory earningId) 
        external 
        view 
        returns (
            uint256 earningIndex,
            address sponsor,
            address token,
            uint256 amount,
            bool claimed
        ) 
    {
        uint256 index = earningIdToIndex[earningId];
        require(index > 0, "SponsorPool: earning not found");
        
        uint256 actualIndex = index - 1;
        Earning memory e = earnings[actualIndex];
        
        return (actualIndex, e.sponsor, e.token, e.amount, e.claimed);
    }

    /**
     * @notice Get sponsor's earnings list
     * @param sponsor Sponsor address
     */
    function getSponsorEarnings(address sponsor) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sponsorEarnings[sponsor];
    }

    /**
     * @notice Get sponsor statistics
     * @param sponsor Sponsor address
     */
    function getSponsorStats(address sponsor) 
        external 
        view 
        returns (
            uint256 totalEarned,
            uint256 totalClaimedAmount,
            uint256 pendingAmount,
            uint256 earningsCount,
            uint256 claimsCount
        ) 
    {
        SponsorStats memory stats = sponsorStats[sponsor];
        return (
            stats.totalEarned,
            stats.totalClaimed,
            stats.pendingAmount,
            stats.earningsCount,
            stats.claimsCount
        );
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
            uint256 totalClaimedAmount,
            uint256 available,
            uint256 earningsCount
        ) 
    {
        return (
            totalCommissionsReceived[token],
            totalClaimed[token],
            IERC20(token).balanceOf(address(this)),
            earnings.length
        );
    }

    /**
     * @notice Get claimable amount for sponsor
     * @param sponsor Sponsor address
     * @param token Token address
     */
    function getClaimableAmount(address sponsor, address token) 
        external 
        view 
        returns (uint256 claimable, uint256 vested) 
    {
        uint256[] memory earningIds = sponsorEarnings[sponsor];
        
        for (uint256 i = 0; i < earningIds.length; i++) {
            Earning memory e = earnings[earningIds[i]];
            
            if (!e.claimed && e.token == token) {
                if (e.vestingEnd == 0 || block.timestamp >= e.vestingEnd) {
                    claimable += e.amount;
                } else {
                    vested += e.amount;
                }
            }
        }
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set minimum claim amount
     * @param amount New minimum amount
     */
    function setMinClaimAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minClaimAmount = amount;
    }

    /**
     * @notice Set default vesting period
     * @param period Vesting period in seconds
     */
    function setDefaultVestingPeriod(uint256 period) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        defaultVestingPeriod = period;
    }

    /**
     * @notice Add supported token
     * @param token Token address to add
     */
    function addSupportedToken(address token) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(token != address(0), "SponsorPool: zero address");
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
        require(to != address(0), "SponsorPool: zero address");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "SponsorPool: no balance");

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
}
