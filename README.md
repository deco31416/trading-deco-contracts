# 🔐 Trading Deco - Smart Contracts v2.0

**Legal-Compliant Utility Token Architecture for AI Trading Platform**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-2.19.4-yellow)](https://hardhat.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.0.1-purple)](https://openzeppelin.com/contracts/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ⚖️ Legal Compliance Notice

These smart contracts implement a **UTILITY TOKEN MODEL**, NOT an investment or security:

- ✅ **Access Token**: DECO tokens provide software access (like API keys)
- ✅ **Consumption Model**: Tokens are consumed during service usage
- ✅ **Non-Custodial**: No holding periods or locked funds
- ✅ **No Investment Language**: No promises of profit, yield, or returns
- ✅ **Circular Economy**: Consumed tokens reallocated to new users

⚠️ **This is NOT a security offering** - Tokens represent utility, not equity.

---

## 📋 Contract Architecture v2.0

### Core Contracts (Legal Compliant)

| Contract | Purpose | Status | Lines |
|----------|---------|--------|-------|
| **DecoAccessToken.sol** | ERC-20 utility access token (1M supply) | ✅ Active | 310 |
| **CrowdfundAccess.sol** | Accept stablecoins, distribute DECO | ✅ Active | 430 |
| **UsageContract.sol** | Lock & consume tokens for AI services | ✅ Active | 480 |
| **TreasuryUsage.sol** | Circular token reallocation | ✅ Active | 490 |

### Archived Contracts (v1.0 - Deprecated)

⚠️ **DO NOT USE** - Replaced by legal-compliant architecture

- `archive/AHTToken.sol` - Old investment-focused token
- `archive/AdminPool.sol` - Old commission pool
- `archive/SponsorPool.sol` - Old sponsor earnings

---

## 🪙 DECO Token Economics

### Token Specifications

```solidity
Name: DecoAccess Token
Symbol: DECO
Decimals: 18
Total Supply: 1,000,000 DECO (fixed)
Initial Allocation: 100,000 DECO (10% for crowdfund)
Reserved: 900,000 DECO (90% for future reallocation)
Blockchain: Binance Smart Chain (BSC)
```

### Distribution Model

- **10% Crowdfund** (100k DECO): Initial token sale to early contributors
- **90% Reserved** (900k DECO): Controlled by TreasuryUsage for:
  - Welcome bonuses (50k/month)
  - Marketing campaigns (100k/month)
  - Community rewards (30k/month)
  - Developer grants (50k/month)
  - Emergency reserves (20k/month)

### Membership Requirements

- **Threshold**: 50 DECO minimum
- **Benefits**: Access to AI trading signals, strategy execution, portfolio analysis
- **No Lockup**: Tokens available immediately after purchase
- **No Staking**: Pure consumption model (no yield, no rewards)

---

## 🔄 How It Works

### 1. Crowdfund Phase (CrowdfundAccess)

```solidity
// User contributes stablecoins (USDC/USDT/BUSD/DAI)
buyAccess(USDC, 100e18, "contribution-001")
// → Receives 1,000 DECO (rate: 10 DECO per USD)
// → Stablecoins go directly to treasury (non-custodial)
```

**Accepted Stablecoins (BSC BEP-20):**
- USDC: `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d`
- USDT: `0x55d398326f99059fF775485246999027B3197955`
- BUSD: `0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56`
- DAI: `0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3`

### 2. Service Usage (UsageContract)

```solidity
// User locks tokens before using AI services (prepayment)
lockAccessTokens(100e18, "lock-001")

// Backend consumes tokens based on actual usage
consumeAccess(user, 0, "AI_SIGNAL_GENERATION", 10, "usage-001")
// → 10 signals × 0.1 DECO = 1 DECO consumed

// User unlocks remaining tokens
unlockTokens(0) // Returns unconsumed balance
```

**Service Pricing:**
- AI Signal Generation: 0.1 DECO per signal
- Strategy Execution: 0.5 DECO per execution
- Portfolio Analysis: 0.2 DECO per analysis
- Market Research: 0.3 DECO per research
- Backtesting: 1.0 DECO per backtest

### 3. Circular Economy (TreasuryUsage)

```solidity
// Treasury receives consumed tokens
receiveConsumedTokens(1e18)

// Reallocate to new users (circular model)
reallocateAccessTokens(newUser, 50e18, "WELCOME_BONUS", "New user incentive")
// → Tokens back in circulation
```

---

## 🏗️ Development Setup

### Prerequisites

- Node.js v18+
- npm or yarn
- BSC wallet with testnet BNB

### Installation

```bash
# Clone repository
git clone https://github.com/deco31416/trading-deco-contracts.git
cd trading-deco-contracts

# Install dependencies
npm install

# Copy environment file
cp .env.example .env
# Edit .env with your PRIVATE_KEY and BSCSCAN_API_KEY
```

### Compile Contracts

```bash
npx hardhat compile
```

### Run Tests

```bash
npx hardhat test
npm run test:coverage
```

### Deploy to BSC Testnet

```bash
npx hardhat run scripts/deploy.ts --network bscTestnet
```

### Deploy to BSC Mainnet

```bash
npx hardhat run scripts/deploy.ts --network bscMainnet
```

### Verify on BscScan

```bash
npx hardhat run scripts/verify.ts --network bscMainnet
```

---

## 📁 Project Structure

```
trading-deco-contracts/
├── contracts/
│   ├── DecoAccessToken.sol       # Main utility token
│   ├── CrowdfundAccess.sol       # Token distribution
│   ├── UsageContract.sol         # Service consumption
│   ├── TreasuryUsage.sol         # Token reallocation
│   └── archive/                  # Deprecated contracts
│       ├── AHTToken.sol
│       ├── AdminPool.sol
│       └── SponsorPool.sol
├── scripts/
│   ├── deploy.ts                 # Deployment script
│   └── verify.ts                 # Verification script
├── test/
│   └── (test files)
├── hardhat.config.ts             # Hardhat configuration
├── package.json
├── tsconfig.json
└── README.md
```

---

## 🔒 Security Features

### OpenZeppelin v5.x Integration

All contracts inherit from audited OpenZeppelin libraries:

- `ERC20`: Standard token implementation
- `ERC20Burnable`: Token burning capability
- `ERC20Pausable`: Emergency pause mechanism
- `Ownable`: Access control
- `ReentrancyGuard`: Prevents reentrancy attacks
- `SafeERC20`: Safe token transfers

### Additional Safeguards

- ✅ Non-custodial design (no user funds held)
- ✅ Rate limiting (contribution/allocation limits)
- ✅ Emergency pause functionality
- ✅ Multi-signature support (for large operations)
- ✅ Event logging (full transparency)
- ✅ Decimal normalization (handles 6/18 decimal tokens)

---

## 🌐 Network Configuration

### BSC Testnet

- **Chain ID**: 97
- **RPC**: `https://data-seed-prebsc-1-s1.binance.org:8545/`
- **Explorer**: https://testnet.bscscan.com
- **Faucet**: https://testnet.bnbchain.org/faucet-smart

### BSC Mainnet

- **Chain ID**: 56
- **RPC**: `https://bsc-dataseed1.binance.org/`
- **Explorer**: https://bscscan.com

---

## 📊 Integration with Backend

### NestJS Integration Example

```typescript
// contracts.service.ts
import { Injectable } from '@nestjs/common';
import { ethers } from 'ethers';

@Injectable()
export class ContractsService {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private decoToken: ethers.Contract;
  private usageContract: ethers.Contract;

  constructor() {
    this.provider = new ethers.JsonRpcProvider(process.env.BSC_RPC_URL);
    this.wallet = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);

    this.decoToken = new ethers.Contract(
      process.env.DECO_TOKEN_ADDRESS,
      DecoAccessTokenABI,
      this.wallet
    );

    this.usageContract = new ethers.Contract(
      process.env.USAGE_CONTRACT_ADDRESS,
      UsageContractABI,
      this.wallet
    );
  }

  // Check if user has membership
  async hasMembership(userAddress: string): Promise<boolean> {
    return await this.decoToken.hasMembership(userAddress);
  }

  // Consume tokens for service usage
  async consumeAccess(
    userAddress: string,
    lockIndex: number,
    serviceType: string,
    units: number,
    usageId: string
  ) {
    const tx = await this.usageContract.consumeAccess(
      userAddress,
      lockIndex,
      serviceType,
      units,
      usageId
    );
    return await tx.wait();
  }

  // Get user's available balance
  async getAvailableBalance(userAddress: string): Promise<string> {
    const balance = await this.usageContract.getAvailableBalance(userAddress);
    return ethers.formatEther(balance);
  }
}
```

---

## 📚 Documentation

- [System Overview](../docs/01-GENERAL/system-overview.md)
- [Smart Contracts Integration](../docs/04-INTEGRACION/smart-contracts-integration.md)
- [Deployment Guide](../docs/05-DEPLOYMENT/railway-deploy.md)
- [Testing Guide](../docs/06-TESTING/integration-testing.md)

---

## 🛠️ Useful Commands

```bash
# Compile contracts
npm run compile

# Run tests
npm run test

# Generate coverage report
npm run test:coverage

# Deploy to testnet
npm run deploy:testnet

# Deploy to mainnet
npm run deploy:mainnet

# Verify contracts
npm run verify

# Clean artifacts
npm run clean

# Lint Solidity files
npm run lint
```

---

## 📊 Contract Addresses

### BSC Testnet (Chain ID: 97)
```
DecoAccessToken:  [Pending Deployment]
CrowdfundAccess:  [Pending Deployment]
UsageContract:    [Pending Deployment]
TreasuryUsage:    [Pending Deployment]
```

### BSC Mainnet (Chain ID: 56)
```
DecoAccessToken:  [Pending Deployment]
CrowdfundAccess:  [Pending Deployment]
UsageContract:    [Pending Deployment]
TreasuryUsage:    [Pending Deployment]
```

---

## ⚖️ Legal Disclaimer

**IMPORTANT**: These smart contracts are designed as a **utility token system**, NOT as:

- ❌ Investment contracts
- ❌ Security offerings
- ❌ Profit-sharing mechanisms
- ❌ Yield-generating protocols

**DECO tokens provide**:

- ✅ Access to AI trading software
- ✅ Consumption-based service usage
- ✅ Membership benefits (like SaaS subscriptions)

**No promises of**:

- ❌ Financial returns
- ❌ Profit or yield
- ❌ Investment gains
- ❌ Passive income

Users acquire tokens to **USE THE SOFTWARE**, not to invest or earn returns.

---

## 📞 Contact & Support

- **Security Issues**: security@tradingdeco.com
- **General Support**: support@tradingdeco.com
- **GitHub Issues**: https://github.com/deco31416/trading-deco-contracts/issues

---

## 📄 License

MIT License - See LICENSE file for details

---

## 👥 Contributors

- **Trading Deco Team** - [GitHub](https://github.com/deco31416)

---

**Version**: 2.0.0 (Legal-Compliant Architecture)  
**Last Updated**: December 2024  
**Solidity Version**: ^0.8.20  
**Network**: Binance Smart Chain (BSC)  

---

**Made with ❤️ by Trading Deco Team**
