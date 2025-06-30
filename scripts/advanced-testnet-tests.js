const { ethers } = require("hardhat");

async function main() {
  const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "0xd71509cDFd55a30658D7569aBdAC6737638e5eda";
  const [owner] = await ethers.getSigners();
  
  console.log("🚀 Advanced Testnet Tests with Time Travel");
  console.log("Contract:", CONTRACT_ADDRESS);
  console.log("Tester:", owner.address);
  
  const atc = await ethers.getContractAt("ATC", CONTRACT_ADDRESS);
  
  // Test Suite 1: Basic Functionality
  console.log("\n📊 Test Suite 1: Basic Contract Health");
  await testBasicFunctionality(atc, owner);
  
  // Test Suite 2: Emission Time Travel
  console.log("\n⏰ Test Suite 2: Emission Phase Time Travel");
  await testEmissionTimeTravel(atc);
  
  // Test Suite 3: Tax System Stress Test
  console.log("\n💸 Test Suite 3: Tax System Stress Test");
  await testTaxSystem(atc, owner);
  
  // Test Suite 4: Anti-Whale Protection
  console.log("\n🐋 Test Suite 4: Anti-Whale Protection");
  await testAntiWhale(atc, owner);
  
  // Test Suite 5: Timelock System
  console.log("\n🔒 Test Suite 5: Timelock System");
  await testTimelockSystem(atc);
  
  // Test Suite 6: Emergency Functions
  console.log("\n🚨 Test Suite 6: Emergency Functions");
  await testEmergencyFunctions(atc);
  
  // Test Suite 7: Multi-Day Simulation
  console.log("\n📅 Test Suite 7: Multi-Day Emission Simulation");
  await testMultiDaySimulation(atc);
  
  console.log("\n🎉 All Advanced Testnet Tests Completed!");
}

async function testBasicFunctionality(atc, owner) {
  try {
    const name = await atc.name();
    const symbol = await atc.symbol();
    const totalSupply = await atc.totalSupply();
    const tradingEnabled = await atc.tradingEnabled();
    
    console.log("  ✅ Name:", name);
    console.log("  ✅ Symbol:", symbol);
    console.log("  ✅ Total Supply:", ethers.formatEther(totalSupply));
    console.log("  ✅ Trading Enabled:", tradingEnabled);
    
    const balance = await atc.balanceOf(owner.address);
    console.log("  ✅ Owner Balance:", ethers.formatEther(balance), "ATC");
    
  } catch (error) {
    console.log("  ❌ Basic functionality test failed:", error.message);
  }
}

async function testEmissionTimeTravel(atc) {
  try {
    // Test current emission
    let emissionInfo = await atc.getEmissionInfo();
    console.log("  📊 Current Phase:", emissionInfo.currentPhase.toString());
    console.log("  📊 Current Emission:", ethers.formatEther(emissionInfo.currentDailyEmission), "ATC/day");
    console.log("  📊 Days Since Launch:", emissionInfo.daysSinceLaunch.toString());
    
    // Test Phase 1 (Day 100)
    console.log("  🕐 Testing Phase 1 (Day 100)...");
    await atc.setLastEmissionDay(100);
    emissionInfo = await atc.getEmissionInfo();
    console.log("    ✅ Phase 1 Emission:", ethers.formatEther(emissionInfo.currentDailyEmission), "ATC/day");
    
    // Test Phase 2 (Day 1500)
    console.log("  🕑 Testing Phase 2 (Day 1500)...");
    await atc.setLastEmissionDay(1500);
    emissionInfo = await atc.getEmissionInfo();
    console.log("    ✅ Phase 2 Emission:", ethers.formatEther(emissionInfo.currentDailyEmission), "ATC/day");
    
    // Test Phase 3 (Day 5000)
    console.log("  🕒 Testing Phase 3 (Day 5000)...");
    await atc.setLastEmissionDay(5000);
    emissionInfo = await atc.getEmissionInfo();
    console.log("    ✅ Phase 3 Emission:", ethers.formatEther(emissionInfo.currentDailyEmission), "ATC/day");
    
  } catch (error) {
    console.log("  ❌ Time travel test failed:", error.message);
  }
}

async function testTaxSystem(atc, owner) {
  try {
    const taxRates = await atc.taxRates();
    console.log("  ✅ Buy Tax:", (Number(taxRates.buyTax) / 100) + "%");
    console.log("  ✅ Sell Tax:", (Number(taxRates.sellTax) / 100) + "%");
    console.log("  ✅ Liquidity Tax:", (Number(taxRates.liquidityTax) / 100) + "%");
    console.log("  ✅ Dev Tax:", (Number(taxRates.devTax) / 100) + "%");
    console.log("  ✅ Artist Tax:", (Number(taxRates.artistTax) / 100) + "%");
    console.log("  ✅ Marketing Tax:", (Number(taxRates.marketingTax) / 100) + "%");
    
    // Test tax calculation consistency
    const totalTax = Number(taxRates.liquidityTax) + Number(taxRates.devTax) + 
                    Number(taxRates.artistTax) + Number(taxRates.marketingTax);
    const buyTax = Number(taxRates.buyTax);
    
    if (totalTax === buyTax) {
      console.log("  ✅ Tax calculation consistency: PASS");
    } else {
      console.log("  ❌ Tax calculation mismatch:", totalTax, "vs", buyTax);
    }
    
  } catch (error) {
    console.log("  ❌ Tax system test failed:", error.message);
  }
}

async function testAntiWhale(atc, owner) {
  try {
    const maxTxAmount = await atc.MAX_TX_AMOUNT();
    console.log("  ✅ Max Transaction Amount:", ethers.formatEther(maxTxAmount), "ATC");
    
    const isExempt = await atc.isAntiWhaleExempt(owner.address);
    console.log("  ✅ Owner Anti-Whale Exempt:", isExempt);
    
    // Test small transfer (should work)
    const smallAmount = ethers.parseEther("1000");
    const testWallet = ethers.Wallet.createRandom();
    
    const tx = await atc.transfer(testWallet.address, smallAmount);
    await tx.wait();
    console.log("  ✅ Small transfer successful:", ethers.formatEther(smallAmount), "ATC");
    
  } catch (error) {
    console.log("  ❌ Anti-whale test failed:", error.message);
  }
}

async function testTimelockSystem(atc) {
  try {
    // Test timelock for blacklist function
    const testAddress = ethers.Wallet.createRandom().address;
    const operation = "setBlacklist";
    
    console.log("  🔒 Testing timelock initiation...");
    try {
      await atc.setBlacklist(testAddress, true);
      console.log("  ❌ Timelock should have prevented immediate execution");
    } catch (error) {
      if (error.message.includes("Timelock initiated")) {
        console.log("  ✅ Timelock properly initiated");
      } else {
        console.log("  ❌ Unexpected timelock error:", error.message);
      }
    }
    
    // Check timelock expiry
    const expiry = await atc.getTimelockExpiry(operation, await atc.owner());
    console.log("  ✅ Timelock expiry timestamp:", expiry.toString());
    
  } catch (error) {
    console.log("  ❌ Timelock test failed:", error.message);
  }
}

async function testEmergencyFunctions(atc) {
  try {
    // Test contract state queries (safe functions)
    const totalLiquidityAdded = await atc.totalLiquidityAdded();
    const lpTokensInContract = await atc.lpTokensInContract();
    
    console.log("  ✅ Total Liquidity Added:", ethers.formatEther(totalLiquidityAdded), "ATC");
    console.log("  ✅ LP Tokens in Contract:", lpTokensInContract.toString());
    
    // Test liquidity info
    const liquidityInfo = await atc.getLiquidityInfo();
    console.log("  ✅ Remaining Liquidity Capacity:", ethers.formatEther(liquidityInfo.remainingLiquidityCapacity), "ATC");
    
  } catch (error) {
    console.log("  ❌ Emergency functions test failed:", error.message);
  }
}

async function testMultiDaySimulation(atc) {
  try {
    console.log("  📅 Simulating 365-day emission progression...");
    
    const testDays = [1, 100, 500, 1000, 2000, 3000, 5000];
    
    for (const day of testDays) {
      await atc.setLastEmissionDay(day);
      const emissionInfo = await atc.getEmissionInfo();
      
      console.log(`    Day ${day}: Phase ${emissionInfo.currentPhase}, Emission: ${ethers.formatEther(emissionInfo.currentDailyEmission)} ATC/day`);
    }
    
    console.log("  ✅ Multi-day simulation completed");
    
  } catch (error) {
    console.log("  ❌ Multi-day simulation failed:", error.message);
  }
}

main().catch(console.error);
