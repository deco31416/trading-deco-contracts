import { run } from "hardhat";
import * as fs from "fs";
import * as path from "path";

/**
 * Verification Script for Trading Deco Smart Contracts
 * 
 * Verifies deployed contracts on BscScan
 * Reads deployment info from deployments/ directory
 */

async function main() {
  console.log("🔍 Starting Contract Verification on BscScan...\n");

  // Get latest deployment file
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  
  if (!fs.existsSync(deploymentsDir)) {
    console.error("❌ No deployments directory found. Deploy contracts first!");
    process.exit(1);
  }

  const files = fs.readdirSync(deploymentsDir).filter(f => f.endsWith(".json"));
  
  if (files.length === 0) {
    console.error("❌ No deployment files found. Deploy contracts first!");
    process.exit(1);
  }

  // Get most recent deployment
  const latestFile = files.sort().reverse()[0];
  const deploymentPath = path.join(deploymentsDir, latestFile);
  const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));

  console.log(`📄 Using deployment file: ${latestFile}`);
  console.log(`📡 Network: ${deployment.network.name}\n`);

  const { contracts, configuration } = deployment;

  try {
    // =========================================
    // 1. Verify AHT Token
    // =========================================
    console.log("🔍 Verifying AHTToken...");
    await run("verify:verify", {
      address: contracts.AHTToken,
      constructorArguments: [
        configuration.treasury,
        configuration.admin,
      ],
    });
    console.log("✅ AHTToken verified!\n");

    // =========================================
    // 2. Verify Admin Pool
    // =========================================
    console.log("🔍 Verifying AdminPool...");
    await run("verify:verify", {
      address: contracts.AdminPool,
      constructorArguments: [
        configuration.treasury,
        configuration.admin,
        configuration.usdt,
        configuration.usdc,
      ],
    });
    console.log("✅ AdminPool verified!\n");

    // =========================================
    // 3. Verify Sponsor Pool
    // =========================================
    console.log("🔍 Verifying SponsorPool...");
    await run("verify:verify", {
      address: contracts.SponsorPool,
      constructorArguments: [
        configuration.admin,
        configuration.usdt,
        configuration.usdc,
      ],
    });
    console.log("✅ SponsorPool verified!\n");

    // =========================================
    // Summary
    // =========================================
    console.log("=" .repeat(60));
    console.log("🎉 ALL CONTRACTS VERIFIED SUCCESSFULLY!");
    console.log("=" .repeat(60));
    console.log("\n🔗 View on BscScan:");
    
    const explorerBase = deployment.network.chainId === "97" 
      ? "https://testnet.bscscan.com/address/"
      : "https://bscscan.com/address/";

    console.log(`   AHTToken:    ${explorerBase}${contracts.AHTToken}`);
    console.log(`   AdminPool:   ${explorerBase}${contracts.AdminPool}`);
    console.log(`   SponsorPool: ${explorerBase}${contracts.SponsorPool}\n`);

  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log("ℹ️  Contracts are already verified on BscScan\n");
    } else {
      console.error("❌ Verification failed:", error.message);
      process.exit(1);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
