// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CoreDecoAccess
 * @dev DECO - Software Utility Access Token (NOT AN INVESTMENT)
 * 
 * LEGAL COMPLIANCE:
 * - This token represents ACCESS to software services, NOT an investment
 * - No promises of profit, yield, dividends, or returns
 * - Tokens are CONSUMED through usage, not staked for rewards
 * - Non-custodial design: users maintain control of their tokens
 * 
 * Token Utility:
 * - Access to AI-powered trading tools
 * - Unlock premium software features
 * - Pay for computational resources
 * - Membership activation
 * 
 * Supply Model:
 * - Fixed supply: 1,000,000 DECO (hard-cap enforced by ERC20Capped)
 * - Initial allocation: 10% (100,000 DECO) for crowdfund phase
 * - Remaining 90% (900,000 DECO) stays unminted until needed
 * 
 * Security Features:
 * - ERC20Capped: Hard cap at 1M tokens (cannot be exceeded)
 * - ERC20Permit: Gasless approvals via signatures (EIP-2612)
 * - AccessControl: Role-based minting permissions
 * - Launch guards: Trading disabled until liquidity is added
 * - Anti-whale: Max transaction/wallet limits (switchable)
 * - Transfer cooldown: Prevents bot spam during launch
 * 
 * Important:
 * - Tokens can be CONSUMED (burned) during software usage
 * - Tokens can be RECYCLED to TreasuryUsage for circular economy
 * - No automatic yields or rewards - purely utility-based
 * 
 * @custom:security-contact security@tradingdeco.com
 * @custom:legal-disclaimer This is NOT a security or investment contract
 */
contract CoreDecoAccess is 
    ERC20, 
    ERC20Burnable, 
    ERC20Pausable, 
    ERC20Permit,
    AccessControl,
    ReentrancyGuard 
{
    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================
    
    error ZeroAddress();
    error ZeroAmount();
    error NotAuthorized();
    error ExceedsCap();
    error TradingDisabled();
    error ExceedsMaxTransaction();
    error ExceedsMaxWallet();
    error CooldownActive();
    error InsufficientBalance();
    error TreasuryNotSet();

    // =============================================================
    //                         CONSTANTS
    // =============================================================
    
    /// @notice Role for minting new tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @notice Maximum token supply cap (1 million)
    uint256 public constant CAP = 1_000_000 * 10**18;
    
    /// @notice Minimum DECO balance required to activate membership
    uint256 public constant MEMBERSHIP_THRESHOLD = 50 * 10**18; // 50 DECO

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice Address of the TreasuryUsage contract
    address public treasuryUsage;
    
    /// @notice Address of the UsageContract
    address public usageContract;
    
    // Launch Guards
    /// @notice Trading enabled flag (starts disabled)
    bool public tradingEnabled;
    
    /// @notice Pre-approved addresses (can transfer before trading enabled)
    mapping(address => bool) public isPreApproved;
    
    // Anti-Whale Limits
    /// @notice Anti-whale limits active flag
    bool public limitsInEffect = true;
    
    /// @notice Maximum tokens per transaction (1% of supply = 10k)
    uint256 public maxTxAmount = 10_000 * 10**18;
    
    /// @notice Maximum tokens per wallet (2% of supply = 20k)
    uint256 public maxWallet = 20_000 * 10**18;
    
    /// @notice Transfer cooldown in seconds (anti-bot)
    uint256 public transferDelay = 20;
    
    /// @notice Last transfer timestamp per address
    mapping(address => uint256) private _lastTransferTimestamp;
    
    /// @notice Addresses exempt from limits (owner, treasury, DEX pairs)
    mapping(address => bool) public isLimitExempt;
    
    // Recycle Mode
    /// @notice If true, consumed tokens go to treasury; if false, burned
    bool public recycleToTreasury = true;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    /// @notice Emitted when tokens are minted for new allocation
    event TokensAllocated(address indexed to, uint256 amount, string reason);
    
    /// @notice Emitted when membership is activated
    event MembershipActivated(address indexed user, uint256 balance);
    
    /// @notice Emitted when tokens are consumed for access
    event AccessConsumed(address indexed user, uint256 amount, string serviceType, bool recycled);
    
    /// @notice Emitted when treasury address is updated
    event TreasuryUsageUpdated(address indexed oldTreasury, address indexed newTreasury);
    
    /// @notice Emitted when usage contract address is updated
    event UsageContractUpdated(address indexed oldUsage, address indexed newUsage);
    
    /// @notice Emitted when trading is enabled/disabled
    event TradingStatusChanged(bool enabled);
    
    /// @notice Emitted when anti-whale limits are updated
    event LimitsUpdated(bool enabled, uint256 maxTx, uint256 maxWallet, uint256 delay);
    
    /// @notice Emitted when recycle mode is changed
    event RecycleModeChanged(bool enabled);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize CoreDecoAccess Token
     * @param multisigOwner Multisig address for secure ownership
     * 
     * @dev Mints 100,000 DECO (10% of cap) to multisig for crowdfund
     * @dev Trading starts DISABLED - enable after adding liquidity
     * @dev Cap enforced at 1,000,000 DECO by ERC20Capped
     */
    constructor(
        address multisigOwner
    ) 
        ERC20("Deco Access Token", "DECO")
        ERC20Permit("Deco Access Token")
    {
        if (multisigOwner == address(0)) revert ZeroAddress();

        // Grant roles to multisig
        _grantRole(DEFAULT_ADMIN_ROLE, multisigOwner);
        _grantRole(MINTER_ROLE, multisigOwner);

        // Mint initial 10% allocation for crowdfund (100k DECO)
        _mint(multisigOwner, 100_000 * 10**18);
        
        // Exempt multisig from limits
        isLimitExempt[multisigOwner] = true;
        isPreApproved[multisigOwner] = true;
        
        // Trading disabled by default (enable after liquidity)
        tradingEnabled = false;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Pause all token transfers (emergency only)
     * @dev Only callable by admin role
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     * @dev Only callable by admin role
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Allocate additional tokens (up to cap)
     * @param to Address to receive tokens
     * @param amount Amount of tokens to allocate
     * @param reason Reason for allocation (e.g., "Marketing Campaign Q1")
     * 
     * @dev Cap enforced automatically by ERC20Capped
     * @dev Only addresses with MINTER_ROLE can call
     */
    function allocateTokens(
        address to,
        uint256 amount,
        string memory reason
    ) external nonReentrant onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // ERC20Capped will revert if exceeds cap
        _mint(to, amount);
        
        emit TokensAllocated(to, amount, reason);
    }

    /**
     * @notice Set TreasuryUsage contract address
     * @param _treasuryUsage Address of TreasuryUsage contract
     */
    function setTreasuryUsage(address _treasuryUsage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasuryUsage == address(0)) revert ZeroAddress();
        address oldTreasury = treasuryUsage;
        treasuryUsage = _treasuryUsage;
        
        // Exempt treasury from limits
        isLimitExempt[_treasuryUsage] = true;
        isPreApproved[_treasuryUsage] = true;
        
        emit TreasuryUsageUpdated(oldTreasury, _treasuryUsage);
    }

    /**
     * @notice Set UsageContract address
     * @param _usageContract Address of UsageContract
     */
    function setUsageContract(address _usageContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_usageContract == address(0)) revert ZeroAddress();
        address oldUsage = usageContract;
        usageContract = _usageContract;
        
        // Exempt usage contract from limits
        isLimitExempt[_usageContract] = true;
        isPreApproved[_usageContract] = true;
        
        emit UsageContractUpdated(oldUsage, _usageContract);
    }

    // =============================================================
    //                   LAUNCH GUARD FUNCTIONS
    // =============================================================

    /**
     * @notice Enable/disable trading
     * @param enabled True to enable trading, false to disable
     * @dev Call this AFTER adding liquidity to DEX
     */
    function setTradingEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tradingEnabled = enabled;
        emit TradingStatusChanged(enabled);
    }

    /**
     * @notice Set pre-approved address (can transfer before trading enabled)
     * @param account Address to approve
     * @param approved True to approve, false to revoke
     */
    function setPreApproved(address account, bool approved) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isPreApproved[account] = approved;
    }

    // =============================================================
    //                  ANTI-WHALE FUNCTIONS
    // =============================================================

    /**
     * @notice Configure anti-whale limits
     * @param _enabled Enable/disable limits
     * @param _maxTxAmount Max tokens per transaction
     * @param _maxWallet Max tokens per wallet
     * @param _transferDelay Cooldown seconds between transfers
     * @dev Set to 0 to effectively disable individual limits
     */
    function setLimits(
        bool _enabled,
        uint256 _maxTxAmount,
        uint256 _maxWallet,
        uint256 _transferDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        limitsInEffect = _enabled;
        maxTxAmount = _maxTxAmount;
        maxWallet = _maxWallet;
        transferDelay = _transferDelay;
        emit LimitsUpdated(_enabled, _maxTxAmount, _maxWallet, _transferDelay);
    }

    /**
     * @notice Set limit exemption for address
     * @param account Address to exempt (e.g., DEX pair, router)
     * @param exempt True to exempt, false to remove exemption
     */
    function setLimitExempt(address account, bool exempt) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        isLimitExempt[account] = exempt;
    }

    // =============================================================
    //                   RECYCLE MODE FUNCTIONS
    // =============================================================

    /**
     * @notice Set recycle mode for consumed tokens
     * @param enabled True = send to treasury, False = burn
     */
    function setRecycleMode(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        recycleToTreasury = enabled;
        emit RecycleModeChanged(enabled);
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @notice Check if user has active membership
     * @param user Address to check
     * @return bool True if user has >= MEMBERSHIP_THRESHOLD DECO
     * 
     * @dev Used by backend to verify membership status
     */
    function hasMembership(address user) external view returns (bool) {
        return balanceOf(user) >= MEMBERSHIP_THRESHOLD;
    }

    /**
     * @notice Get detailed membership status
     * @param user Address to check
     * @return hasAccess True if user has membership
     * @return currentBalance Current DECO balance
     * @return required Required DECO amount (50)
     * @return shortfall Amount needed to reach membership (0 if already has)
     */
    function getMembershipStatus(address user) 
        external 
        view 
        returns (
            bool hasAccess,
            uint256 currentBalance,
            uint256 required,
            uint256 shortfall
        ) 
    {
        currentBalance = balanceOf(user);
        required = MEMBERSHIP_THRESHOLD;
        hasAccess = currentBalance >= required;
        shortfall = hasAccess ? 0 : required - currentBalance;
    }

    /**
     * @notice Activate membership (emit event for backend tracking)
     * @dev User must have >= MEMBERSHIP_THRESHOLD DECO
     */
    function activateMembership() external {
        uint256 balance = balanceOf(msg.sender);
        if (balance < MEMBERSHIP_THRESHOLD) revert InsufficientBalance();
        emit MembershipActivated(msg.sender, balance);
    }

    /**
     * @notice Consume tokens for service access
     * @param amount Amount of DECO to consume
     * @param serviceType Type of service being accessed
     * 
     * @dev If recycleToTreasury=true: transfers to treasury (circular economy)
     * @dev If recycleToTreasury=false: burns tokens (deflationary)
     * @dev Non-custodial: user signs and calls directly
     */
    function consumeAccess(uint256 amount, string memory serviceType) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        
        bool recycled = false;
        
        if (recycleToTreasury && treasuryUsage != address(0)) {
            // Circular economy: send to treasury for reallocation
            _transfer(msg.sender, treasuryUsage, amount);
            recycled = true;
        } else {
            // Deflationary: burn tokens
            _burn(msg.sender, amount);
        }
        
        emit AccessConsumed(msg.sender, amount, serviceType, recycled);
    }

    /**
     * @notice Get token information
     * @return tokenName Token name
     * @return tokenSymbol Token symbol
     * @return tokenDecimals Token decimals
     * @return supply Total minted supply
     * @return maxSupply Maximum possible supply (cap)
     * @return remaining Remaining tokens that can be minted
     */
    function getTokenInfo() 
        external 
        view 
        returns (
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals,
            uint256 supply,
            uint256 maxSupply,
            uint256 remaining
        ) 
    {
        return (
            name(),
            symbol(),
            decimals(),
            totalSupply(),
            CAP,
            CAP - totalSupply()
        );
    }

    // =============================================================
    //                    INTERNAL OVERRIDES
    // =============================================================

    /**
     * @dev Override with launch guards, anti-whale protection, and cap enforcement
     * @dev Called on every transfer, mint, and burn
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) {
        // Cap enforcement (for mints)
        if (from == address(0)) {
            // This is a mint
            if (totalSupply() + amount > CAP) revert ExceedsCap();
        }

        // Launch Guard: Check if trading is enabled
        if (!tradingEnabled) {
            // Allow if either sender or receiver is pre-approved
            if (!isPreApproved[from] && !isPreApproved[to]) {
                revert TradingDisabled();
            }
        }

        // Anti-Whale Protection (skip for mints/burns and exempt addresses)
        if (
            limitsInEffect &&
            from != address(0) && // not a mint
            to != address(0) &&   // not a burn
            !isLimitExempt[from] &&
            !isLimitExempt[to]
        ) {
            // Max transaction limit
            if (amount > maxTxAmount) revert ExceedsMaxTransaction();

            // Max wallet limit (only check receiver)
            if (balanceOf(to) + amount > maxWallet) revert ExceedsMaxWallet();

            // Transfer cooldown (anti-bot)
            if (block.timestamp - _lastTransferTimestamp[from] < transferDelay) {
                revert CooldownActive();
            }
            _lastTransferTimestamp[from] = block.timestamp;
        }

        super._update(from, to, amount);
    }
}
