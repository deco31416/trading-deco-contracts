// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title UsageContract
 * @dev Contract for locking and consuming DECO tokens for AI service access
 * 
 * LEGAL COMPLIANCE:
 * - This is a SERVICE CONSUMPTION model, NOT staking or yield generation
 * - Users lock tokens temporarily while using services
 * - Tokens are progressively consumed based on actual usage
 * - Consumed tokens are transferred to TreasuryUsage for reallocation
 * - NO rewards, NO profit sharing, NO financial returns
 * 
 * Usage Flow:
 * 1. User locks DECO tokens before using AI services
 * 2. Backend tracks actual service usage (API calls, compute time)
 * 3. Contract consumes tokens proportional to usage
 * 4. Consumed tokens go to TreasuryUsage (circular economy)
 * 5. Remaining locked tokens can be unlocked at any time
 * 
 * Service Types:
 * - AI_SIGNAL_GENERATION: Market signals from AI agents
 * - STRATEGY_EXECUTION: Automated strategy execution
 * - PORTFOLIO_ANALYSIS: AI portfolio optimization
 * - MARKET_RESEARCH: AI-powered market research
 * - BACKTESTING: Historical strategy testing
 * 
 * Important:
 * - Lock tokens = prepay for service access (like a utility bill)
 * - Consume tokens = actual usage charges
 * - Unlock tokens = refund unused prepayment
 * - Treasury reallocation = circular token economy
 * 
 * @custom:security-contact security@tradingdeco.com
 * @custom:legal-disclaimer This is NOT a staking or investment contract
 */
contract UsageContract is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          STRUCTS
    // =============================================================
    
    /**
     * @dev Service type configuration
     */
    struct ServiceType {
        string name;
        uint256 costPerUnit; // DECO tokens per unit of service
        bool active;
        uint256 totalConsumed; // Total tokens consumed for this service
    }

    /**
     * @dev User lock record
     */
    struct LockRecord {
        uint256 amount;
        uint256 lockedAt;
        uint256 consumedAmount;
        bool active;
        string lockId; // For backend tracking
    }

    /**
     * @dev Consumption record
     */
    struct ConsumptionRecord {
        address user;
        string serviceType;
        uint256 amount;
        uint256 timestamp;
        uint256 lockIndex;
        string usageId; // For backend tracking
    }

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice DECO token contract
    IERC20 public decoToken;
    
    /// @notice TreasuryUsage contract (receives consumed tokens)
    address public treasuryUsage;
    
    /// @notice Mapping: service type ID => ServiceType config
    mapping(string => ServiceType) public serviceTypes;
    
    /// @notice List of all service type IDs
    string[] public serviceTypeIds;
    
    /// @notice Mapping: user => lock records
    mapping(address => LockRecord[]) public userLocks;
    
    /// @notice All consumption records
    ConsumptionRecord[] public consumptions;
    
    /// @notice Mapping: user => consumption indices
    mapping(address => uint256[]) public userConsumptions;
    
    /// @notice Total tokens locked across all users
    uint256 public totalLocked;
    
    /// @notice Total tokens consumed across all services
    uint256 public totalConsumed;
    
    /// @notice Mapping: user => total locked
    mapping(address => uint256) public userTotalLocked;
    
    /// @notice Mapping: user => total consumed
    mapping(address => uint256) public userTotalConsumed;
    
    /// @notice Minimum lock amount
    uint256 public minLockAmount;
    
    /// @notice Authorized backends (can consume tokens on behalf of users)
    mapping(address => bool) public authorizedBackends;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    event TokensLocked(
        address indexed user,
        uint256 amount,
        uint256 lockIndex,
        string lockId
    );
    
    event AccessConsumed(
        address indexed user,
        string serviceType,
        uint256 amount,
        uint256 lockIndex,
        string usageId
    );
    
    event TokensUnlocked(
        address indexed user,
        uint256 amount,
        uint256 lockIndex
    );
    
    event ServiceTypeAdded(string serviceTypeId, uint256 costPerUnit);
    event ServiceTypeUpdated(string serviceTypeId, uint256 newCost);
    event TreasuryUsageUpdated(address indexed oldTreasury, address indexed newTreasury);
    event BackendAuthorized(address indexed backend);
    event BackendRevoked(address indexed backend);

    // =============================================================
    //                          MODIFIERS
    // =============================================================
    
    modifier onlyAuthorized() {
        require(
            authorizedBackends[msg.sender] || msg.sender == owner(),
            "Usage: not authorized"
        );
        _;
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize Usage contract
     * @param _decoToken Address of DECO token
     * @param _treasuryUsage Address of TreasuryUsage contract
     * @param initialOwner Owner address
     */
    constructor(
        address _decoToken,
        address _treasuryUsage,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_decoToken != address(0), "Usage: zero DECO address");
        require(_treasuryUsage != address(0), "Usage: zero treasury address");

        decoToken = IERC20(_decoToken);
        treasuryUsage = _treasuryUsage;
        minLockAmount = 1 * 10**18; // 1 DECO minimum

        // Initialize default service types
        _addServiceType("AI_SIGNAL_GENERATION", 1 * 10**17); // 0.1 DECO per signal
        _addServiceType("STRATEGY_EXECUTION", 5 * 10**17); // 0.5 DECO per execution
        _addServiceType("PORTFOLIO_ANALYSIS", 2 * 10**17); // 0.2 DECO per analysis
        _addServiceType("MARKET_RESEARCH", 3 * 10**17); // 0.3 DECO per research
        _addServiceType("BACKTESTING", 1 * 10**18); // 1 DECO per backtest
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @notice Lock DECO tokens for service access (prepayment)
     * @param amount Amount of DECO to lock
     * @param lockId Unique ID for tracking (from backend)
     * 
     * @dev Tokens are locked, not staked. No rewards generated.
     */
    function lockAccessTokens(uint256 amount, string memory lockId) external nonReentrant whenNotPaused {
        require(amount >= minLockAmount, "Usage: below minimum");
        require(bytes(lockId).length > 0, "Usage: empty lock ID");

        // Transfer DECO from user to contract
        decoToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create lock record
        userLocks[msg.sender].push(LockRecord({
            amount: amount,
            lockedAt: block.timestamp,
            consumedAmount: 0,
            active: true,
            lockId: lockId
        }));

        uint256 lockIndex = userLocks[msg.sender].length - 1;

        // Update totals
        totalLocked += amount;
        userTotalLocked[msg.sender] += amount;

        emit TokensLocked(msg.sender, amount, lockIndex, lockId);
    }

    /**
     * @notice Consume locked tokens for service usage
     * @param user User address
     * @param lockIndex Index of lock record to consume from
     * @param serviceTypeId Type of service being consumed
     * @param units Number of service units consumed
     * @param usageId Unique ID for tracking (from backend)
     * 
     * @dev Only authorized backends can call this
     * @dev Consumed tokens are transferred to TreasuryUsage
     */
    function consumeAccess(
        address user,
        uint256 lockIndex,
        string memory serviceTypeId,
        uint256 units,
        string memory usageId
    ) external onlyAuthorized nonReentrant whenNotPaused {
        require(user != address(0), "Usage: zero address");
        require(lockIndex < userLocks[user].length, "Usage: invalid lock index");
        require(bytes(usageId).length > 0, "Usage: empty usage ID");

        // Get service type
        ServiceType storage service = serviceTypes[serviceTypeId];
        require(service.active, "Usage: service not active");

        // Calculate consumption amount
        uint256 consumeAmount = service.costPerUnit * units;
        require(consumeAmount > 0, "Usage: zero consumption");

        // Get lock record
        LockRecord storage lock = userLocks[user][lockIndex];
        require(lock.active, "Usage: lock not active");

        uint256 available = lock.amount - lock.consumedAmount;
        require(available >= consumeAmount, "Usage: insufficient locked tokens");

        // Update lock record
        lock.consumedAmount += consumeAmount;

        // If fully consumed, deactivate lock
        if (lock.consumedAmount >= lock.amount) {
            lock.active = false;
        }

        // Update service totals
        service.totalConsumed += consumeAmount;

        // Update global totals
        totalConsumed += consumeAmount;
        userTotalConsumed[user] += consumeAmount;

        // Transfer consumed tokens to TreasuryUsage
        decoToken.safeTransfer(treasuryUsage, consumeAmount);

        // Record consumption
        consumptions.push(ConsumptionRecord({
            user: user,
            serviceType: serviceTypeId,
            amount: consumeAmount,
            timestamp: block.timestamp,
            lockIndex: lockIndex,
            usageId: usageId
        }));

        uint256 consumptionIndex = consumptions.length - 1;
        userConsumptions[user].push(consumptionIndex);

        emit AccessConsumed(user, serviceTypeId, consumeAmount, lockIndex, usageId);
    }

    /**
     * @notice Unlock remaining tokens from a lock
     * @param lockIndex Index of lock to unlock
     * 
     * @dev Returns unconsumed tokens to user
     */
    function unlockTokens(uint256 lockIndex) external nonReentrant whenNotPaused {
        require(lockIndex < userLocks[msg.sender].length, "Usage: invalid lock index");

        LockRecord storage lock = userLocks[msg.sender][lockIndex];
        require(lock.active, "Usage: lock not active");

        uint256 remaining = lock.amount - lock.consumedAmount;
        require(remaining > 0, "Usage: no tokens to unlock");

        // Deactivate lock
        lock.active = false;

        // Update totals
        totalLocked -= remaining;
        userTotalLocked[msg.sender] -= remaining;

        // Transfer remaining tokens back to user
        decoToken.safeTransfer(msg.sender, remaining);

        emit TokensUnlocked(msg.sender, remaining, lockIndex);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get user's active locks
     */
    function getActiveLocks(address user) external view returns (LockRecord[] memory) {
        LockRecord[] memory locks = userLocks[user];
        uint256 activeCount = 0;

        // Count active locks
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].active) {
                activeCount++;
            }
        }

        // Create result array
        LockRecord[] memory activeLocks = new LockRecord[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].active) {
                activeLocks[index] = locks[i];
                index++;
            }
        }

        return activeLocks;
    }

    /**
     * @notice Get user's total available locked tokens
     */
    function getAvailableBalance(address user) external view returns (uint256) {
        LockRecord[] memory locks = userLocks[user];
        uint256 total = 0;

        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].active) {
                total += (locks[i].amount - locks[i].consumedAmount);
            }
        }

        return total;
    }

    /**
     * @notice Get user's consumption history
     */
    function getConsumptions(address user) external view returns (uint256[] memory) {
        return userConsumptions[user];
    }

    /**
     * @notice Get all service types
     */
    function getServiceTypes() external view returns (string[] memory) {
        return serviceTypeIds;
    }

    /**
     * @notice Calculate cost for service units
     */
    function calculateCost(string memory serviceTypeId, uint256 units) external view returns (uint256) {
        return serviceTypes[serviceTypeId].costPerUnit * units;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Add new service type
     */
    function addServiceType(string memory serviceTypeId, uint256 costPerUnit) external onlyOwner {
        _addServiceType(serviceTypeId, costPerUnit);
    }

    /**
     * @notice Update service type cost
     */
    function updateServiceCost(string memory serviceTypeId, uint256 newCost) external onlyOwner {
        require(serviceTypes[serviceTypeId].costPerUnit > 0, "Usage: service not found");
        serviceTypes[serviceTypeId].costPerUnit = newCost;
        emit ServiceTypeUpdated(serviceTypeId, newCost);
    }

    /**
     * @notice Set TreasuryUsage address
     */
    function setTreasuryUsage(address _treasuryUsage) external onlyOwner {
        require(_treasuryUsage != address(0), "Usage: zero address");
        address oldTreasury = treasuryUsage;
        treasuryUsage = _treasuryUsage;
        emit TreasuryUsageUpdated(oldTreasury, _treasuryUsage);
    }

    /**
     * @notice Set minimum lock amount
     */
    function setMinLockAmount(uint256 _minLockAmount) external onlyOwner {
        require(_minLockAmount > 0, "Usage: invalid amount");
        minLockAmount = _minLockAmount;
    }

    /**
     * @notice Authorize backend to consume tokens
     */
    function authorizeBackend(address backend) external onlyOwner {
        require(backend != address(0), "Usage: zero address");
        authorizedBackends[backend] = true;
        emit BackendAuthorized(backend);
    }

    /**
     * @notice Revoke backend authorization
     */
    function revokeBackend(address backend) external onlyOwner {
        authorizedBackends[backend] = false;
        emit BackendRevoked(backend);
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

    function _addServiceType(string memory serviceTypeId, uint256 costPerUnit) internal {
        require(bytes(serviceTypeId).length > 0, "Usage: empty service ID");
        require(costPerUnit > 0, "Usage: invalid cost");
        require(serviceTypes[serviceTypeId].costPerUnit == 0, "Usage: service exists");

        serviceTypes[serviceTypeId] = ServiceType({
            name: serviceTypeId,
            costPerUnit: costPerUnit,
            active: true,
            totalConsumed: 0
        });

        serviceTypeIds.push(serviceTypeId);
        emit ServiceTypeAdded(serviceTypeId, costPerUnit);
    }
}
