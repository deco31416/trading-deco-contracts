// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CrowdfundAccess
 * @dev Crowdfund contract for DECO access token allocation (NOT A SECURITY SALE)
 * 
 * LEGAL COMPLIANCE:
 * - This is a DONATION/CONTRIBUTION model, NOT an investment
 * - Contributors receive utility tokens for software access
 * - No promises of profit, returns, or financial gains
 * - Non-custodial: stablecoins go directly to treasury (no holding period)
 * 
 * Accepted Payment Tokens (BSC BEP-20):
 * - USDC: 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
 * - USDT: 0x55d398326f99059fF775485246999027B3197955
 * - BUSD: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
 * - DAI:  0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3
 * 
 * Crowdfund Model:
 * - Contributors send stablecoins to contract
 * - Contract immediately transfers to treasury (no custody)
 * - Contract sends DECO tokens to contributor
 * - Exchange rate: defined by owner (e.g., 1 USD = 10 DECO)
 * 
 * Important:
 * - Tokens represent SOFTWARE ACCESS, not equity or profit-sharing
 * - No lockup periods (tokens available immediately)
 * - No vesting schedules or unlock mechanisms
 * - Pure utility: use tokens to access AI services
 * 
 * @custom:security-contact security@tradingdeco.com
 * @custom:legal-disclaimer This is NOT a security offering
 */
contract CrowdfundAccess is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          STRUCTS
    // =============================================================
    
    /**
     * @dev Accepted stablecoin configuration
     */
    struct AcceptedToken {
        address tokenAddress;
        uint8 decimals;
        bool active;
        string symbol;
    }

    /**
     * @dev Contribution record
     */
    struct Contribution {
        address contributor;
        address stablecoin;
        uint256 stablecoinAmount;
        uint256 decoReceived;
        uint256 timestamp;
        string contributionId; // For backend tracking
    }

    // =============================================================
    //                          STORAGE
    // =============================================================
    
    /// @notice DECO token contract
    IERC20 public decoToken;
    
    /// @notice Treasury address (receives all stablecoins)
    address public treasury;
    
    /// @notice Exchange rate: amount of DECO per 1 USD (with 18 decimals)
    /// @dev Example: 10 * 1e18 = 10 DECO per 1 USD
    uint256 public decoPerUsd;
    
    /// @notice List of accepted stablecoins
    AcceptedToken[] public acceptedTokens;
    
    /// @notice Mapping: stablecoin address => array index
    mapping(address => uint256) public tokenIndex;
    
    /// @notice Mapping: stablecoin address => is accepted
    mapping(address => bool) public isAcceptedToken;
    
    /// @notice All contributions
    Contribution[] public contributions;
    
    /// @notice Mapping: contributor => contribution IDs
    mapping(address => uint256[]) public contributorContributions;
    
    /// @notice Total stablecoin value contributed (in USD, 18 decimals)
    uint256 public totalContributedUsd;
    
    /// @notice Total DECO tokens distributed
    uint256 public totalDecoDistributed;
    
    /// @notice Minimum contribution amount (in USD, 18 decimals)
    uint256 public minContributionUsd;
    
    /// @notice Maximum contribution amount per address (in USD, 18 decimals)
    uint256 public maxContributionPerAddress;
    
    /// @notice Crowdfund active status
    bool public crowdfundActive;

    // =============================================================
    //                           EVENTS
    // =============================================================
    
    event AccessPurchased(
        address indexed contributor,
        address indexed stablecoin,
        uint256 stablecoinAmount,
        uint256 decoAmount,
        string contributionId
    );
    
    event StablecoinAdded(address indexed token, string symbol, uint8 decimals);
    event StablecoinRemoved(address indexed token);
    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event CrowdfundStatusChanged(bool active);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================
    
    /**
     * @notice Initialize Crowdfund contract
     * @param _decoToken Address of DECO token
     * @param _treasury Address to receive stablecoins
     * @param _decoPerUsd Initial exchange rate (DECO per 1 USD)
     * @param initialOwner Owner address
     */
    constructor(
        address _decoToken,
        address _treasury,
        uint256 _decoPerUsd,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_decoToken != address(0), "Crowdfund: zero DECO address");
        require(_treasury != address(0), "Crowdfund: zero treasury address");
        require(_decoPerUsd > 0, "Crowdfund: invalid exchange rate");

        decoToken = IERC20(_decoToken);
        treasury = _treasury;
        decoPerUsd = _decoPerUsd;
        
        // Default limits
        minContributionUsd = 10 * 10**18; // 10 USD minimum
        maxContributionPerAddress = 100_000 * 10**18; // 100k USD max per address
        
        crowdfundActive = true;

        // Initialize accepted stablecoins (BSC mainnet)
        _addStablecoin(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, "USDC", 18);
        _addStablecoin(0x55d398326f99059fF775485246999027B3197955, "USDT", 18);
        _addStablecoin(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56, "BUSD", 18);
        _addStablecoin(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3, "DAI", 18);
    }

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @notice Buy DECO access tokens with stablecoins
     * @param stablecoin Address of stablecoin to use
     * @param amount Amount of stablecoin to contribute
     * @param contributionId Unique ID for tracking (from backend)
     * 
     * @dev Non-custodial: stablecoins go directly to treasury
     * @dev DECO tokens sent immediately to contributor
     */
    function buyAccess(
        address stablecoin,
        uint256 amount,
        string memory contributionId
    ) external nonReentrant whenNotPaused {
        require(crowdfundActive, "Crowdfund: not active");
        require(isAcceptedToken[stablecoin], "Crowdfund: token not accepted");
        require(amount > 0, "Crowdfund: zero amount");
        require(bytes(contributionId).length > 0, "Crowdfund: empty contribution ID");

        // Get stablecoin info
        AcceptedToken memory tokenInfo = acceptedTokens[tokenIndex[stablecoin]];
        require(tokenInfo.active, "Crowdfund: token not active");

        // Calculate USD value (normalize to 18 decimals)
        uint256 usdValue = _normalizeAmount(amount, tokenInfo.decimals);
        
        // Check limits
        require(usdValue >= minContributionUsd, "Crowdfund: below minimum");
        
        uint256 totalContributed = _getTotalContributedByAddress(msg.sender) + usdValue;
        require(
            totalContributed <= maxContributionPerAddress,
            "Crowdfund: exceeds max per address"
        );

        // Calculate DECO amount to distribute
        uint256 decoAmount = (usdValue * decoPerUsd) / 10**18;
        require(decoAmount > 0, "Crowdfund: DECO amount is zero");

        // Check DECO balance
        uint256 decoBalance = decoToken.balanceOf(address(this));
        require(decoBalance >= decoAmount, "Crowdfund: insufficient DECO balance");

        // Transfer stablecoin from contributor to treasury (NON-CUSTODIAL)
        IERC20(stablecoin).safeTransferFrom(msg.sender, treasury, amount);

        // Transfer DECO to contributor
        decoToken.safeTransfer(msg.sender, decoAmount);

        // Record contribution
        contributions.push(Contribution({
            contributor: msg.sender,
            stablecoin: stablecoin,
            stablecoinAmount: amount,
            decoReceived: decoAmount,
            timestamp: block.timestamp,
            contributionId: contributionId
        }));

        uint256 contributionIndex = contributions.length - 1;
        contributorContributions[msg.sender].push(contributionIndex);

        // Update totals
        totalContributedUsd += usdValue;
        totalDecoDistributed += decoAmount;

        emit AccessPurchased(msg.sender, stablecoin, amount, decoAmount, contributionId);
    }

    /**
     * @notice Donate for access (alias for buyAccess with clearer name)
     */
    function donateForAccess(
        address stablecoin,
        uint256 amount,
        string memory contributionId
    ) external {
        // Calls buyAccess internally
        this.buyAccess(stablecoin, amount, contributionId);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get contributor's total contributions in USD
     */
    function getTotalContributed(address contributor) external view returns (uint256) {
        return _getTotalContributedByAddress(contributor);
    }

    /**
     * @notice Get contributor's contribution history
     */
    function getContributions(address contributor) external view returns (uint256[] memory) {
        return contributorContributions[contributor];
    }

    /**
     * @notice Get accepted stablecoins list
     */
    function getAcceptedTokens() external view returns (AcceptedToken[] memory) {
        return acceptedTokens;
    }

    /**
     * @notice Calculate DECO amount for USD value
     */
    function calculateDecoAmount(uint256 usdAmount) external view returns (uint256) {
        return (usdAmount * decoPerUsd) / 10**18;
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Set exchange rate (DECO per USD)
     */
    function setExchangeRate(uint256 _decoPerUsd) external onlyOwner {
        require(_decoPerUsd > 0, "Crowdfund: invalid rate");
        uint256 oldRate = decoPerUsd;
        decoPerUsd = _decoPerUsd;
        emit ExchangeRateUpdated(oldRate, _decoPerUsd);
    }

    /**
     * @notice Set treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Crowdfund: zero address");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Set contribution limits
     */
    function setLimits(uint256 _minUsd, uint256 _maxUsd) external onlyOwner {
        require(_minUsd > 0, "Crowdfund: invalid min");
        require(_maxUsd > _minUsd, "Crowdfund: max must be > min");
        minContributionUsd = _minUsd;
        maxContributionPerAddress = _maxUsd;
    }

    /**
     * @notice Activate/deactivate crowdfund
     */
    function setCrowdfundStatus(bool active) external onlyOwner {
        crowdfundActive = active;
        emit CrowdfundStatusChanged(active);
    }

    /**
     * @notice Add accepted stablecoin
     */
    function addStablecoin(address token, string memory symbol, uint8 decimals) external onlyOwner {
        _addStablecoin(token, symbol, decimals);
    }

    /**
     * @notice Remove accepted stablecoin
     */
    function removeStablecoin(address token) external onlyOwner {
        require(isAcceptedToken[token], "Crowdfund: token not found");
        
        uint256 index = tokenIndex[token];
        acceptedTokens[index].active = false;
        isAcceptedToken[token] = false;
        
        emit StablecoinRemoved(token);
    }

    /**
     * @notice Emergency withdraw DECO (if needed)
     */
    function emergencyWithdrawDeco(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Crowdfund: zero address");
        decoToken.safeTransfer(to, amount);
    }

    /**
     * @notice Pause crowdfund
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause crowdfund
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    function _addStablecoin(address token, string memory symbol, uint8 decimals) internal {
        require(token != address(0), "Crowdfund: zero address");
        require(!isAcceptedToken[token], "Crowdfund: already added");
        
        acceptedTokens.push(AcceptedToken({
            tokenAddress: token,
            decimals: decimals,
            active: true,
            symbol: symbol
        }));
        
        tokenIndex[token] = acceptedTokens.length - 1;
        isAcceptedToken[token] = true;
        
        emit StablecoinAdded(token, symbol, decimals);
    }

    function _normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        } else if (decimals < 18) {
            return amount * 10**(18 - decimals);
        } else {
            return amount / 10**(decimals - 18);
        }
    }

    function _getTotalContributedByAddress(address contributor) internal view returns (uint256) {
        uint256[] memory contribIds = contributorContributions[contributor];
        uint256 total = 0;
        
        for (uint256 i = 0; i < contribIds.length; i++) {
            Contribution memory contrib = contributions[contribIds[i]];
            AcceptedToken memory tokenInfo = acceptedTokens[tokenIndex[contrib.stablecoin]];
            uint256 usdValue = _normalizeAmount(contrib.stablecoinAmount, tokenInfo.decimals);
            total += usdValue;
        }
        
        return total;
    }
}
