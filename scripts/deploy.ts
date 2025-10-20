import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Deployment Script for Trading Deco Smart Contracts
 * 
 * Deploys:
 * 1. AHTToken (ERC20)
 * 2. AdminPool (10% commission management)
 * 3. SponsorPool (10% sponsor earnings)
 * 
 * Network: BSC Testnet (Chain ID 97) or BSC Mainnet (Chain ID 56)
 */

async function main() {
  console.log("🚀 Starting Trading Deco Contracts Deployment...\n");

  // Get network info
  const network = await ethers.provider.getNetwork();
  console.log(`📡 Network: ${network.name} (Chain ID: ${network.chainId})\n`);

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log(`👤 Deployer: ${deployer.address}`);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} BNB\n`);

  // Configuration from environment variables
  const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS || deployer.address;
  const ADMIN_ADDRESS = process.env.ADMIN_ADDRESS || deployer.address;
  
  // Token addresses based on network
  let USDT_ADDRESS: string;
  let USDC_ADDRESS: string;

  if (network.chainId === 97n) {
    // BSC Testnet
    USDT_ADDRESS = process.env.USDT_TESTNET || "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd";
    USDC_ADDRESS = process.env.USDC_TESTNET || "0x64544969ed7EBf5f083679233325356EbE738930";
  } else if (network.chainId === 56n) {
    // BSC Mainnet
    USDT_ADDRESS = process.env.USDT_MAINNET || "0x55d398326f99059fF775485246999027B3197955";
    USDC_ADDRESS = process.env.USDC_MAINNET || "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
  } else {
    // Local Hardhat network (use mock addresses)
    USDT_ADDRESS = "0x0000000000000000000000000000000000000001";
    USDC_ADDRESS = "0x0000000000000000000000000000000000000002";
    console.log("⚠️  Using mock token addresses for local network\n");
  }

  console.log("📋 Configuration:");
  console.log(`   Treasury: ${TREASURY_ADDRESS}`);
  console.log(`   Admin: ${ADMIN_ADDRESS}`);
  console.log(`   USDT: ${USDT_ADDRESS}`);
  console.log(`   USDC: ${USDC_ADDRESS}\n`);

  // Deployment storage
  const deployedContracts: Record<string, string> = {};

  try {
    // =========================================
    // 1. Deploy AHT Token
    // =========================================
    console.log("📦 Deploying AHTToken...");
    const AHTToken = await ethers.getContractFactory("AHTToken");
    const ahtToken = await AHTToken.deploy(TREASURY_ADDRESS, ADMIN_ADDRESS);
    await ahtToken.waitForDeployment();
    const ahtTokenAddress = await ahtToken.getAddress();
    
    console.log(`✅ AHTToken deployed at: ${ahtTokenAddress}\n`);
    deployedContracts.AHTToken = ahtTokenAddress;

    // =========================================
    // 2. Deploy Admin Pool
    // =========================================
    console.log("📦 Deploying AdminPool...");
    const AdminPool = await ethers.getContractFactory("AdminPool");
    const adminPool = await AdminPool.deploy(
      TREASURY_ADDRESS,
      ADMIN_ADDRESS,
      USDT_ADDRESS,
      USDC_ADDRESS
    );
    await adminPool.waitForDeployment();
    const adminPoolAddress = await adminPool.getAddress();
    
    console.log(`✅ AdminPool deployed at: ${adminPoolAddress}\n`);
    deployedContracts.AdminPool = adminPoolAddress;

    // =========================================
    // 3. Deploy Sponsor Pool
    // =========================================
    console.log("📦 Deploying SponsorPool...");
    const SponsorPool = await ethers.getContractFactory("SponsorPool");
    const sponsorPool = await SponsorPool.deploy(
      ADMIN_ADDRESS,
      USDT_ADDRESS,
      USDC_ADDRESS
    );
    await sponsorPool.waitForDeployment();
    const sponsorPoolAddress = await sponsorPool.getAddress();
    
    console.log(`✅ SponsorPool deployed at: ${sponsorPoolAddress}\n`);
    deployedContracts.SponsorPool = sponsorPoolAddress;

    // =========================================
    // Save Deployment Info
    // =========================================
    const deploymentInfo = {
      network: {
        name: network.name,
        chainId: network.chainId.toString(),
      },
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: deployedContracts,
      configuration: {
        treasury: TREASURY_ADDRESS,
        admin: ADMIN_ADDRESS,
        usdt: USDT_ADDRESS,
        usdc: USDC_ADDRESS,
      },
    };

    const deploymentDir = path.join(__dirname, "..", "deployments");
    if (!fs.existsSync(deploymentDir)) {
      fs.mkdirSync(deploymentDir, { recursive: true });
    }

    const filename = `deployment-${network.name}-${Date.now()}.json`;
    const filepath = path.join(deploymentDir, filename);
    fs.writeFileSync(filepath, JSON.stringify(deploymentInfo, null, 2));

    console.log(`💾 Deployment info saved to: ${filename}\n`);

    // =========================================
    // Summary
    // =========================================
    console.log("=" .repeat(60));
    console.log("🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!");
    console.log("=" .repeat(60));
    console.log("\n📝 Contract Addresses:");
    console.log(`   AHTToken:    ${ahtTokenAddress}`);
    console.log(`   AdminPool:   ${adminPoolAddress}`);
    console.log(`   SponsorPool: ${sponsorPoolAddress}`);
    console.log("\n🔗 Next Steps:");
    console.log("   1. Verify contracts on BscScan: yarn verify:testnet");
    console.log("   2. Setup roles: yarn setup:testnet");
    console.log("   3. Update backend .env with contract addresses");
    console.log("   4. Test contract interactions\n");

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
