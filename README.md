# 🔐 Trading Deco - Smart Contracts

**Professional Smart Contracts for Trading Deco Platform on Binance Smart Chain (BSC)**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-2.19.4-yellow)](https://hardhat.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.0.1-purple)](https://openzeppelin.com/contracts/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📋 **Tabla de Contenidos**

- [Descripción](#-descripción)
- [Contratos](#-contratos)
- [Arquitectura](#-arquitectura)
- [Instalación](#-instalación)
- [Deployment](#-deployment)
- [Testing](#-testing)
- [Seguridad](#-seguridad)
- [Integración con Backend](#-integración-con-backend)

---

## 🎯 **Descripción**

Este repositorio contiene los **Smart Contracts** de la plataforma **Trading Deco**, diseñados para gestionar:

- 💎 **Token AHT** (Algo Hybrid Trading): Token ERC20 de la plataforma
- 💰 **AdminPool**: Gestión del 10% de comisiones administrativas
- 🤝 **SponsorPool**: Gestión del 10% de comisiones de referidos

Todos los contratos están desplegados en **Binance Smart Chain (BSC)** y siguen los estándares de **OpenZeppelin v5**.

---

## 📦 **Contratos**

### **1️⃣ AHTToken.sol** (280 líneas)
**Token ERC20 de la plataforma**

- **Supply fijo**: 1,000,000 AHT
- **Decimales**: 18
- **Premium Panel**: Requiere 300+ AHT
- **Features**: Burnable, Pausable, Access Control
- **Roles**: ADMIN, MINTER, PAUSER

```solidity
// Verificar premium status
bool isPremium = ahtToken.hasPremiumStatus(userAddress);

// Check premium details
(bool hasAccess, uint256 balance, uint256 required, uint256 shortfall) 
    = ahtToken.checkPremiumStatus(userAddress);
```

---

### **2️⃣ AdminPool.sol** (450 líneas)
**Pool de comisiones administrativas (10%)**

- **Recibe**: 10% de comisiones de ciclos completados
- **Distribución**: 40% Operations, 30% Development, 15% Marketing, 15% Reserve
- **Features**: Stakeholder management, distribution history
- **Roles**: ADMIN, OPERATOR, AUDITOR, DISTRIBUTOR

```solidity
// Backend envia comisión
adminPool.receiveCommission(usdtAddress, amount, cycleId);

// Admin distribuye fondos
adminPool.distribute(usdtAddress, 0, "Monthly distribution Q4 2025");
```

---

### **3️⃣ SponsorPool.sol** (550 líneas)
**Pool de comisiones de sponsors (10%)**

- **Recibe**: 10% de comisiones de referidos
- **Claims**: Individuales o batch (hasta 50 por transacción)
- **Features**: Vesting opcional, statistics tracking
- **Roles**: ADMIN, OPERATOR, AUDITOR

```solidity
// Backend registra earning
sponsorPool.recordEarning(sponsorAddress, usdtAddress, amount, earningId, cycleId, 0);

// Sponsor hace claim
sponsorPool.claimEarning(earningIndex);

// Batch claims (gas-efficient)
sponsorPool.claimMultipleEarnings([0, 1, 2, 3]);
```

---

## 🏗️ **Arquitectura**

```
Usuario completa ciclo 200% 
         ↓
Backend calcula comisión 20%
         ↓
    ┌────────────┐
    │ 20% Split  │
    └────────────┘
         ↓
    ┌─────┴─────┐
    ↓           ↓
10% Admin   10% Sponsor
    ↓           ↓
AdminPool  SponsorPool
(on-chain) (on-chain)
```

**Tokens soportados**: USDT, USDC (BSC)

---

## 🚀 **Instalación**

### **Requisitos**
- Node.js >= 18
- Yarn o npm
- Wallet con BNB (para gas)

### **Setup**

```bash
# Clonar repositorio
git clone https://github.com/deco31416/trading-deco-contracts.git
cd trading-deco-contracts

# Instalar dependencias
npm install
# o
yarn install

# Copiar variables de entorno
cp .env.example .env
```

### **Configurar .env**

```env
# Private key (sin 0x)
PRIVATE_KEY=your_private_key_here

# BscScan API Key
BSCSCAN_API_KEY=your_bscscan_api_key_here

# Addresses
TREASURY_ADDRESS=your_treasury_wallet
ADMIN_ADDRESS=your_admin_wallet
```

---

## 🌐 **Deployment**

### **Compilar Contratos**
```bash
npx hardhat compile
```

### **Deploy en BSC Testnet**
```bash
npx hardhat run scripts/deploy.ts --network bscTestnet
```

### **Deploy en BSC Mainnet**
```bash
npx hardhat run scripts/deploy.ts --network bscMainnet
```

### **Verificar en BscScan**
```bash
# Testnet
npx hardhat run scripts/verify.ts --network bscTestnet

# Mainnet
npx hardhat run scripts/verify.ts --network bscMainnet
```

---

## 🧪 **Testing**

```bash
# Run tests
npx hardhat test

# Coverage
npx hardhat coverage

# Gas report
REPORT_GAS=true npx hardhat test
```

---

## 🔒 **Seguridad**

### **Auditoría Completa ✅**

| Protección | Implementación |
|------------|----------------|
| **Reentrancy** | ✅ `ReentrancyGuard` + `nonReentrant` |
| **Race Conditions** | ✅ Checks-Effects-Interactions |
| **Overflow/Underflow** | ✅ Solidity 0.8.20 (auto) |
| **Access Control** | ✅ OpenZeppelin `AccessControl` |
| **Pausable** | ✅ Emergency stop mechanism |
| **Safe Transfers** | ✅ `SafeERC20` |

### **Roles y Permisos**

#### **AHTToken**
- `DEFAULT_ADMIN_ROLE`: Control total
- `MINTER_ROLE`: Mintear tokens (vesting)
- `PAUSER_ROLE`: Pausar/despausar

#### **AdminPool**
- `DEFAULT_ADMIN_ROLE`: Control total
- `OPERATOR_ROLE`: Recibir comisiones
- `DISTRIBUTOR_ROLE`: Distribuir fondos
- `AUDITOR_ROLE`: Ver estadísticas

#### **SponsorPool**
- `DEFAULT_ADMIN_ROLE`: Control total
- `OPERATOR_ROLE`: Registrar earnings
- `AUDITOR_ROLE`: Ver estadísticas

---

## 🔗 **Integración con Backend**

### **1. Instalación en Backend NestJS**

```bash
cd ../trading-deco  # Backend repo
yarn add ethers@6
```

### **2. Crear BlockchainService**

```typescript
// src/blockchain/blockchain.service.ts
import { Injectable } from '@nestjs/common';
import { ethers } from 'ethers';

@Injectable()
export class BlockchainService {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  
  // Contract instances
  private adminPool: ethers.Contract;
  private sponsorPool: ethers.Contract;

  constructor() {
    this.provider = new ethers.JsonRpcProvider(process.env.BSC_RPC_URL);
    this.wallet = new ethers.Wallet(process.env.OPERATOR_PRIVATE_KEY, this.provider);
    
    // Initialize contracts
    this.adminPool = new ethers.Contract(
      process.env.ADMIN_POOL_ADDRESS,
      AdminPoolABI,
      this.wallet
    );
    
    this.sponsorPool = new ethers.Contract(
      process.env.SPONSOR_POOL_ADDRESS,
      SponsorPoolABI,
      this.wallet
    );
  }

  async sendAdminCommission(token: string, amount: string, cycleId: string) {
    const tx = await this.adminPool.receiveCommission(token, amount, cycleId);
    return await tx.wait();
  }

  async recordSponsorEarning(
    sponsor: string,
    token: string,
    amount: string,
    earningId: string,
    cycleId: string
  ) {
    const tx = await this.sponsorPool.recordEarning(
      sponsor,
      token,
      amount,
      earningId,
      cycleId,
      0 // no vesting
    );
    return await tx.wait();
  }
}
```

### **3. Modificar PaymentsService**

```typescript
// src/modules/payments/payments.service.ts
async calculateAndCreateCommission(cycle: TradingCycle) {
  // ... cálculos existentes ...
  
  // 🔥 Enviar a blockchain
  const adminCommission = totalCommission * 0.5; // 10%
  const sponsorCommission = totalCommission * 0.5; // 10%
  
  // Send to AdminPool
  await this.blockchainService.sendAdminCommission(
    usdtAddress,
    ethers.parseUnits(adminCommission.toString(), 6), // USDT = 6 decimals
    cycle._id.toString()
  );
  
  // Send to SponsorPool
  await this.blockchainService.recordSponsorEarning(
    sponsorWallet,
    usdtAddress,
    ethers.parseUnits(sponsorCommission.toString(), 6),
    earningDoc._id.toString(),
    cycle._id.toString()
  );
}
```

---

## 📊 **Contract Addresses**

### **BSC Testnet (Chain ID: 97)**
```
AHTToken:    [Pending Deployment]
AdminPool:   [Pending Deployment]
SponsorPool: [Pending Deployment]
```

### **BSC Mainnet (Chain ID: 56)**
```
AHTToken:    [Pending Deployment]
AdminPool:   [Pending Deployment]
SponsorPool: [Pending Deployment]
```

---

## 📚 **Recursos**

- [Hardhat Documentation](https://hardhat.org/docs)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [BSC Documentation](https://docs.bnbchain.org/)
- [BscScan API](https://docs.bscscan.com/)
- [Ethers.js v6](https://docs.ethers.org/v6/)

---

## 👥 **Contributors**

- **Trading Deco Team** - [GitHub](https://github.com/deco31416)

---

## 📄 **License**

MIT License - see [LICENSE](LICENSE) file for details

---

## 🆘 **Support**

- **Email**: security@tradingdeco.com
- **GitHub Issues**: [Create Issue](https://github.com/deco31416/trading-deco-contracts/issues)

---

**Made with ❤️ by Trading Deco Team**
