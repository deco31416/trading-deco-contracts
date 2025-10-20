// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DecoAccessToken
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
 * - Fixed supply: 1,000,000 DECO (cannot be increased)
 * - Initial allocation: 10% (100,000 DECO) for crowdfund phase
 * - Remaining 90% (900,000 DECO) stays unminted until needed
 * 
 * Important:
 * - Tokens can be CONSUMED (burned) during software usage
 * - Tokens can be transferred to TreasuryUsage for circular usability
 * - No automatic yields or rewards - purely utility-based
 * 
 * @custom:security-contact security@tradingdeco.com
 * @custom:legal-disclaimer This is NOT a security or investment contract
 */
contract DecoAccessToken is 
    ERC20, 
    ERC20Burnable, 
    ERC20Pausable, 
    Ownable, 
    ReentrancyGuard 
{
    // =============================================================
    //                         CONSTANTS
    // =============================================================
    
    /// @notice Total supply of DECO tokens (1 million)
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
    
    /// @notice Initial allocation for crowdfund (10% of total)
    uint256 public constant INITIAL_ALLOCATION = TOTAL_SUPPLY / 10; // 100,000 DECO
    
    /// @notice Minimum DECO balance required to activate membership
    uint256 public constant MEMBERSHIP_THRESHOLD = 50 * 10**18; // 50 DECO

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice Total minted supply (cannot exceed TOTAL_SUPPLY)
    uint256 public totalMinted;
    
    /// @notice Address of the TreasuryUsage contract
    address public treasuryUsage;
    
    /// @notice Address of the UsageContract
    address public usageContract;
    
    /// @notice Mapping of addresses with minting permission
    mapping(address => bool) public canMint;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    /// @notice Emitted when tokens are minted for new allocation
    event TokensAllocated(address indexed to, uint256 amount, string reason);
    
    /// @notice Emitted when membership is activated
    event MembershipActivated(address indexed user, uint256 balance);
    
    /// @notice Emitted when tokens are consumed for access
    event AccessConsumed(address indexed user, uint256 amount, string serviceType);
    
    /// @notice Emitted when treasury address is updated
    event TreasuryUsageUpdated(address indexed oldTreasury, address indexed newTreasury);
    
    /// @notice Emitted when usage contract address is updated
    event UsageContractUpdated(address indexed oldUsage, address indexed newUsage);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize DecoAccess Token
     * @param initialOwner Address to receive ownership and initial allocation
     * 
     * @dev Mints INITIAL_ALLOCATION (10% = 100k tokens) to owner for crowdfund
     */
    constructor(
        address initialOwner
    ) ERC20("Deco Access Token", "DECO") Ownable(initialOwner) {
        require(initialOwner != address(0), "DECO: owner is zero address");

        // Mint initial 10% allocation for crowdfund
        _mint(initialOwner, INITIAL_ALLOCATION);
        totalMinted = INITIAL_ALLOCATION;
        
        // Owner can mint additional tokens (up to TOTAL_SUPPLY)
        canMint[initialOwner] = true;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Pause all token transfers (emergency only)
     * @dev Only callable by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     * @dev Only callable by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Allocate additional tokens (up to TOTAL_SUPPLY)
     * @param to Address to receive tokens
     * @param amount Amount of tokens to allocate
     * @param reason Reason for allocation (e.g., "Crowdfund Phase 2")
     * 
     * @dev Can only mint up to TOTAL_SUPPLY
     * @dev Only addresses with canMint permission can call
     */
    function allocateTokens(
        address to,
        uint256 amount,
        string memory reason
    ) external nonReentrant {
        require(canMint[msg.sender], "DECO: not authorized to mint");
        require(to != address(0), "DECO: mint to zero address");
        require(amount > 0, "DECO: mint amount is zero");
        require(
            totalMinted + amount <= TOTAL_SUPPLY,
            "DECO: exceeds total supply"
        );

        _mint(to, amount);
        totalMinted += amount;
        
        emit TokensAllocated(to, amount, reason);
    }

    /**
     * @notice Set TreasuryUsage contract address
     * @param _treasuryUsage Address of TreasuryUsage contract
     */
    function setTreasuryUsage(address _treasuryUsage) external onlyOwner {
        require(_treasuryUsage != address(0), "DECO: zero address");
        address oldTreasury = treasuryUsage;
        treasuryUsage = _treasuryUsage;
        emit TreasuryUsageUpdated(oldTreasury, _treasuryUsage);
    }

    /**
     * @notice Set UsageContract address
     * @param _usageContract Address of UsageContract
     */
    function setUsageContract(address _usageContract) external onlyOwner {
        require(_usageContract != address(0), "DECO: zero address");
        address oldUsage = usageContract;
        usageContract = _usageContract;
        emit UsageContractUpdated(oldUsage, _usageContract);
    }

    /**
     * @notice Grant or revoke minting permission
     * @param account Address to grant/revoke permission
     * @param permission True to grant, false to revoke
     */
    function setMintPermission(address account, bool permission) external onlyOwner {
        require(account != address(0), "DECO: zero address");
        canMint[account] = permission;
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
        require(balance >= MEMBERSHIP_THRESHOLD, "DECO: insufficient balance for membership");
        emit MembershipActivated(msg.sender, balance);
    }

    /**
     * @notice Consume tokens for service access
     * @param amount Amount of DECO to consume (burn)
     * @param serviceType Type of service being accessed
     * 
     * @dev Tokens are burned (permanently destroyed)
     */
    function consumeAccess(uint256 amount, string memory serviceType) external nonReentrant {
        require(amount > 0, "DECO: consume amount is zero");
        require(balanceOf(msg.sender) >= amount, "DECO: insufficient balance");
        
        _burn(msg.sender, amount);
        emit AccessConsumed(msg.sender, amount, serviceType);
    }

    /**
     * @notice Get token information
     * @return name Token name
     * @return symbol Token symbol
     * @return decimals Token decimals
     * @return supply Total minted supply
     * @return maxSupply Maximum possible supply
     * @return remaining Remaining tokens that can be minted
     */
    function getTokenInfo() 
        external 
        view 
        returns (
            string memory name,
            string memory symbol,
            uint8 decimals,
            uint256 supply,
            uint256 maxSupply,
            uint256 remaining
        ) 
    {
        return (
            name(),
            symbol(),
            decimals(),
            totalMinted,
            TOTAL_SUPPLY,
            TOTAL_SUPPLY - totalMinted
        );
    }

    // =============================================================
    //                    INTERNAL OVERRIDES
    // =============================================================

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, amount);
    }
}
