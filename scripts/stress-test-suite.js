const { ethers } = require("hardhat");

async function main() {
  const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "0xd71509cDFd55a30658D7569aBdAC6737638e5eda";
  const [owner] = await ethers.getSigners();
  
  console.log("💪 Stress Testing ATC Contract");
  console.log("Contract:", CONTRACT_ADDRESS);
  
  const atc = await ethers.getContractAt("ATC", CONTRACT_ADDRESS);
  
  // Stress Test 1: Rapid Transfers
  console.log("\n🚀 Stress Test 1: Rapid Transfer Sequence");
  await rapidTransferTest(atc, owner);
  
  // Stress Test 2: Emission Edge Cases
  console.log("\n⚡ Stress Test 2: Emission Edge Cases");
  await emissionEdgeCases(atc);
  
  // Stress Test 3: Gas Usage Analysis
  console.log("\n⛽ Stress Test 3: Gas Usage Analysis");
  await gasUsageAnalysis(atc, owner);
  
  console.log("\n🎯 Stress Testing Complete!");
}

async function rapidTransferTest(atc, owner) {
  try {
    const recipients = [];
    for (let i = 0; i < 5; i++) {
      recipients.push(ethers.Wallet.createRandom().address);
    }
    
    console.log("  🔄 Executing 5 rapid transfers...");
    
    for (let i = 0; i < recipients.length; i++) {
      const amount = ethers.parseEther(`${(i + 1) * 100}`);
      const tx = await atc.transfer(recipients[i], amount);
      const receipt = await tx.wait();
      
      console.log(`    Transfer ${i + 1}: ${ethers.formatEther(amount)} ATC, Gas: ${receipt.gasUsed.toString()}`);
    }
    
    console.log("  ✅ Rapid transfer test completed");
    
  } catch (error) {
    console.log("  ❌ Rapid transfer test failed:", error.message);
  }
}

async function emissionEdgeCases(atc) {
  try {
    // Test boundary conditions
    const edgeDays = [729, 730, 731, 2919, 2920, 2921];
    
    console.log("  🎯 Testing emission phase boundaries...");
    
    for (const day of edgeDays) {
      await atc.setLastEmissionDay(day);
      const emissionInfo = await atc.getEmissionInfo();
      
      console.log(`    Day ${day}: Phase ${emissionInfo.currentPhase}, Emission: ${ethers.formatEther(emissionInfo.currentDailyEmission)} ATC`);
    }
    
    console.log("  ✅ Edge case testing completed");
    
  } catch (error) {
    console.log("  ❌ Edge case testing failed:", error.message);
  }
}

async function gasUsageAnalysis(atc, owner) {
  try {
    // Test different function gas costs
    const testWallet = ethers.Wallet.createRandom().address;
    
    console.log("  ⛽ Analyzing gas usage for key functions...");
    
    // Transfer
    const transferTx = await atc.transfer(testWallet, ethers.parseEther("100"));
    const transferReceipt = await transferTx.wait();
    console.log(`    Transfer: ${transferReceipt.gasUsed.toString()} gas`);
    
    // Emission update
    const emissionTx = await atc.setLastEmissionDay(1000);
    const emissionReceipt = await emissionTx.wait();
    console.log(`    Emission Update: ${emissionReceipt.gasUsed.toString()} gas`);
    
    console.log("  ✅ Gas analysis completed");
    
  } catch (error) {
    console.log("  ❌ Gas analysis failed:", error.message);
  }
}

main().catch(console.error);
