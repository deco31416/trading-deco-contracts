// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TreasuryUsage
 * @dev Treasury contract for circular DECO token economy
 * 
 * LEGAL COMPLIANCE:
 * - This is a UTILITY TOKEN REALLOCATION system, NOT profit distribution
 * - Receives consumed tokens from UsageContract
 * - Reallocates tokens to new users (circular economy)
 * - NO dividends, NO profit sharing, NO yield generation
 * - Pure utility: recycle consumed tokens back into circulation
 * 
 * Treasury Functions:
 * 1. Receive consumed tokens from UsageContract
 * 2. Track token circulation statistics
 * 3. Reallocate tokens for platform operations:
 *    - New user incentives (welcome bonuses)
 *    - Marketing campaigns (airdrops)
 *    - Community rewards (bug bounties)
 *    - Developer grants (ecosystem growth)
 *    - Emergency reserves (platform stability)
 * 
 * Important Distinctions:
 * - Reallocation ≠ Investment returns (no profit promise)
 * - Token recycling ≠ Yield farming (no financial gains)
 * - Treasury ≠ Dividend pool (no investor payouts)
 * - Circular economy = sustainability model
 * 
 * Transparency:
 * - All reallocations are tracked on-chain
 * - Public statistics for token circulation
 * - Multi-signature controls for large amounts
 * 
 * @custom:security-contact security@tradingdeco.com
 * @custom:legal-disclaimer This is NOT a profit-sharing mechanism
 */
contract TreasuryUsage is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          STRUCTS
    // =============================================================
    
    /**
     * @dev Reallocation category
     */
    struct AllocationCategory {
        string name;
        uint256 totalAllocated;
        uint256 limit; // Maximum allocation per period
        bool active;
    }

    /**
     * @dev Reallocation record
     */
    struct AllocationRecord {
        address recipient;
        uint256 amount;
        string category;
        string reason;
        uint256 timestamp;
        address allocator;
    }

    /**
     * @dev Withdrawal record
     */
    struct WithdrawalRecord {
        address destination;
        uint256 amount;
        string purpose;
        uint256 timestamp;
        address executor;
    }

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice DECO token contract
    IERC20 public decoToken;
    
    /// @notice UsageContract address (authorized to send consumed tokens)
    address public usageContract;
    
    /// @notice Mapping: category ID => AllocationCategory
    mapping(string => AllocationCategory) public categories;
    
    /// @notice List of all category IDs
    string[] public categoryIds;
    
    /// @notice All allocation records
    AllocationRecord[] public allocations;
    
    /// @notice All withdrawal records
    WithdrawalRecord[] public withdrawals;
    
    /// @notice Mapping: recipient => allocation indices
    mapping(address => uint256[]) public recipientAllocations;
    
    /// @notice Total tokens received from consumption
    uint256 public totalReceived;
    
    /// @notice Total tokens reallocated
    uint256 public totalReallocated;
    
    /// @notice Total tokens withdrawn for operations
    uint256 public totalWithdrawn;
    
    /// @notice Current period (resets periodically for limits)
    uint256 public currentPeriod;
    
    /// @notice Period duration (default 30 days)
    uint256 public periodDuration;
    
    /// @notice Period start timestamp
    uint256 public periodStart;
    
    /// @notice Mapping: period => category => allocated amount
    mapping(uint256 => mapping(string => uint256)) public periodAllocations;
    
    /// @notice Multi-signature threshold for large reallocations
    uint256 public multiSigThreshold;
    
    /// @notice Authorized allocators (can reallocate tokens)
    mapping(address => bool) public authorizedAllocators;
    
    /// @notice Emergency stop (only owner can activate)
    bool public emergencyStop;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    event TokensReceived(address indexed from, uint256 amount, uint256 newBalance);
    
    event TokensReallocated(
        address indexed recipient,
        uint256 amount,
        string category,
        string reason,
        address indexed allocator
    );
    
    event TokensWithdrawn(
        address indexed destination,
        uint256 amount,
        string purpose,
        address indexed executor
    );
    
    event CategoryAdded(string categoryId, uint256 limit);
    event CategoryUpdated(string categoryId, uint256 newLimit);
    event PeriodReset(uint256 newPeriod, uint256 timestamp);
    event AllocatorAuthorized(address indexed allocator);
    event AllocatorRevoked(address indexed allocator);
    event UsageContractUpdated(address indexed oldContract, address indexed newContract);
    event EmergencyStopActivated(uint256 timestamp);
    event EmergencyStopDeactivated(uint256 timestamp);

    // =============================================================
    //                          MODIFIERS
    // =============================================================
    
    modifier onlyAuthorizedAllocator() {
        require(
            authorizedAllocators[msg.sender] || msg.sender == owner(),
            "Treasury: not authorized allocator"
        );
        _;
    }

    modifier onlyUsageContract() {
        require(msg.sender == usageContract, "Treasury: not usage contract");
        _;
    }

    modifier whenNotEmergency() {
        require(!emergencyStop, "Treasury: emergency stop active");
        _;
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize Treasury contract
     * @param _decoToken Address of DECO token
     * @param _usageContract Address of UsageContract
     * @param initialOwner Owner address
     */
    constructor(
        address _decoToken,
        address _usageContract,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_decoToken != address(0), "Treasury: zero DECO address");
        require(_usageContract != address(0), "Treasury: zero usage contract");

        decoToken = IERC20(_decoToken);
        usageContract = _usageContract;
        
        // Period configuration
        periodDuration = 30 days;
        periodStart = block.timestamp;
        currentPeriod = 1;
        
        // Multi-sig threshold (10,000 DECO)
        multiSigThreshold = 10_000 * 10**18;

        // Initialize allocation categories
        _addCategory("WELCOME_BONUS", 50_000 * 10**18); // 50k DECO per month
        _addCategory("MARKETING", 100_000 * 10**18); // 100k DECO per month
        _addCategory("COMMUNITY_REWARDS", 30_000 * 10**18); // 30k DECO per month
        _addCategory("DEVELOPER_GRANTS", 50_000 * 10**18); // 50k DECO per month
        _addCategory("EMERGENCY_RESERVE", 20_000 * 10**18); // 20k DECO per month
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @notice Receive consumed tokens from UsageContract
     * @param amount Amount of tokens received
     * 
     * @dev Only UsageContract can call this
     */
    function receiveConsumedTokens(uint256 amount) external onlyUsageContract {
        require(amount > 0, "Treasury: zero amount");
        
        totalReceived += amount;
        uint256 newBalance = decoToken.balanceOf(address(this));
        
        emit TokensReceived(msg.sender, amount, newBalance);
    }

    /**
     * @notice Reallocate tokens to recipient
     * @param recipient Address to receive tokens
     * @param amount Amount of tokens
     * @param category Allocation category
     * @param reason Reason for allocation
     * 
     * @dev Only authorized allocators can call
     * @dev Subject to category limits per period
     */
    function reallocateAccessTokens(
        address recipient,
        uint256 amount,
        string memory category,
        string memory reason
    ) external onlyAuthorizedAllocator nonReentrant whenNotPaused whenNotEmergency {
        require(recipient != address(0), "Treasury: zero address");
        require(amount > 0, "Treasury: zero amount");
        require(bytes(category).length > 0, "Treasury: empty category");
        require(bytes(reason).length > 0, "Treasury: empty reason");

        // Check if period needs reset
        _checkPeriodReset();

        // Get category
        AllocationCategory storage cat = categories[category];
        require(cat.active, "Treasury: category not active");

        // Check period limit
        uint256 periodAllocated = periodAllocations[currentPeriod][category];
        require(
            periodAllocated + amount <= cat.limit,
            "Treasury: exceeds category limit"
        );

        // Check balance
        uint256 balance = decoToken.balanceOf(address(this));
        require(balance >= amount, "Treasury: insufficient balance");

        // Update period allocations
        periodAllocations[currentPeriod][category] += amount;
        cat.totalAllocated += amount;

        // Update totals
        totalReallocated += amount;

        // Transfer tokens
        decoToken.safeTransfer(recipient, amount);

        // Record allocation
        allocations.push(AllocationRecord({
            recipient: recipient,
            amount: amount,
            category: category,
            reason: reason,
            timestamp: block.timestamp,
            allocator: msg.sender
        }));

        uint256 allocationIndex = allocations.length - 1;
        recipientAllocations[recipient].push(allocationIndex);

        emit TokensReallocated(recipient, amount, category, reason, msg.sender);
    }

    /**
     * @notice Withdraw tokens for operational expenses
     * @param destination Address to receive tokens
     * @param amount Amount of tokens
     * @param purpose Purpose of withdrawal
     * 
     * @dev Only owner can call
     * @dev For operational expenses, not user rewards
     */
    function withdrawForOperations(
        address destination,
        uint256 amount,
        string memory purpose
    ) external onlyOwner nonReentrant whenNotPaused whenNotEmergency {
        require(destination != address(0), "Treasury: zero address");
        require(amount > 0, "Treasury: zero amount");
        require(bytes(purpose).length > 0, "Treasury: empty purpose");

        uint256 balance = decoToken.balanceOf(address(this));
        require(balance >= amount, "Treasury: insufficient balance");

        // Update totals
        totalWithdrawn += amount;

        // Transfer tokens
        decoToken.safeTransfer(destination, amount);

        // Record withdrawal
        withdrawals.push(WithdrawalRecord({
            destination: destination,
            amount: amount,
            purpose: purpose,
            timestamp: block.timestamp,
            executor: msg.sender
        }));

        emit TokensWithdrawn(destination, amount, purpose, msg.sender);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get current treasury balance
     */
    function getBalance() external view returns (uint256) {
        return decoToken.balanceOf(address(this));
    }

    /**
     * @notice Get recipient's allocation history
     */
    function getAllocations(address recipient) external view returns (uint256[] memory) {
        return recipientAllocations[recipient];
    }

    /**
     * @notice Get all categories
     */
    function getCategories() external view returns (string[] memory) {
        return categoryIds;
    }

    /**
     * @notice Get category remaining limit for current period
     */
    function getCategoryRemainingLimit(string memory category) external view returns (uint256) {
        AllocationCategory memory cat = categories[category];
        if (!cat.active) return 0;
        
        uint256 used = periodAllocations[currentPeriod][category];
        if (used >= cat.limit) return 0;
        
        return cat.limit - used;
    }

    /**
     * @notice Get total allocations count
     */
    function getTotalAllocations() external view returns (uint256) {
        return allocations.length;
    }

    /**
     * @notice Get total withdrawals count
     */
    function getTotalWithdrawals() external view returns (uint256) {
        return withdrawals.length;
    }

    /**
     * @notice Get time until next period reset
     */
    function getTimeUntilReset() external view returns (uint256) {
        uint256 periodEnd = periodStart + periodDuration;
        if (block.timestamp >= periodEnd) return 0;
        return periodEnd - block.timestamp;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Add allocation category
     */
    function addCategory(string memory categoryId, uint256 limit) external onlyOwner {
        _addCategory(categoryId, limit);
    }

    /**
     * @notice Update category limit
     */
    function updateCategoryLimit(string memory categoryId, uint256 newLimit) external onlyOwner {
        require(categories[categoryId].active, "Treasury: category not found");
        categories[categoryId].limit = newLimit;
        emit CategoryUpdated(categoryId, newLimit);
    }

    /**
     * @notice Set period duration
     */
    function setPeriodDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Treasury: invalid duration");
        periodDuration = _duration;
    }

    /**
     * @notice Manually reset period (emergency)
     */
    function resetPeriod() external onlyOwner {
        _resetPeriod();
    }

    /**
     * @notice Set UsageContract address
     */
    function setUsageContract(address _usageContract) external onlyOwner {
        require(_usageContract != address(0), "Treasury: zero address");
        address oldContract = usageContract;
        usageContract = _usageContract;
        emit UsageContractUpdated(oldContract, _usageContract);
    }

    /**
     * @notice Set multi-sig threshold
     */
    function setMultiSigThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold > 0, "Treasury: invalid threshold");
        multiSigThreshold = _threshold;
    }

    /**
     * @notice Authorize allocator
     */
    function authorizeAllocator(address allocator) external onlyOwner {
        require(allocator != address(0), "Treasury: zero address");
        authorizedAllocators[allocator] = true;
        emit AllocatorAuthorized(allocator);
    }

    /**
     * @notice Revoke allocator
     */
    function revokeAllocator(address allocator) external onlyOwner {
        authorizedAllocators[allocator] = false;
        emit AllocatorRevoked(allocator);
    }

    /**
     * @notice Activate emergency stop
     */
    function activateEmergencyStop() external onlyOwner {
        emergencyStop = true;
        emit EmergencyStopActivated(block.timestamp);
    }

    /**
     * @notice Deactivate emergency stop
     */
    function deactivateEmergencyStop() external onlyOwner {
        emergencyStop = false;
        emit EmergencyStopDeactivated(block.timestamp);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    function _addCategory(string memory categoryId, uint256 limit) internal {
        require(bytes(categoryId).length > 0, "Treasury: empty category ID");
        require(limit > 0, "Treasury: invalid limit");
        require(!categories[categoryId].active, "Treasury: category exists");

        categories[categoryId] = AllocationCategory({
            name: categoryId,
            totalAllocated: 0,
            limit: limit,
            active: true
        });

        categoryIds.push(categoryId);
        emit CategoryAdded(categoryId, limit);
    }

    function _checkPeriodReset() internal {
        uint256 periodEnd = periodStart + periodDuration;
        if (block.timestamp >= periodEnd) {
            _resetPeriod();
        }
    }

    function _resetPeriod() internal {
        currentPeriod++;
        periodStart = block.timestamp;
        emit PeriodReset(currentPeriod, block.timestamp);
    }
}
