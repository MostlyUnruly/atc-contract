const { ethers } = require("hardhat");

async function main() {
  const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || "0xd71509cDFd55a30658D7569aBdAC6737638e5eda";
  const [owner] = await ethers.getSigners();
  
  console.log("🧪 Testing Live ATC Contract on BSC Testnet");
  console.log("Contract:", CONTRACT_ADDRESS);
  console.log("Tester:", owner.address);
  
  const atc = await ethers.getContractAt("ATC", CONTRACT_ADDRESS);
  
  // Test 1: Basic contract info
  console.log("\n📊 Contract Information:");
  console.log("Name:", await atc.name());
  console.log("Symbol:", await atc.symbol());
  console.log("Total Supply:", ethers.formatEther(await atc.totalSupply()));
  console.log("Trading Enabled:", await atc.tradingEnabled());
  
  // Test 2: Owner balance
  console.log("\n💰 Owner Balance:");
  const balance = await atc.balanceOf(owner.address);
  console.log("Owner has:", ethers.formatEther(balance), "ATC");
  
  // Test 3: Tax rates
  console.log("\n💸 Tax Configuration:");
  const taxRates = await atc.taxRates();
  console.log("Buy Tax:", (Number(taxRates.buyTax) / 100) + "%");
  console.log("Sell Tax:", (Number(taxRates.sellTax) / 100) + "%");
  
  // Test 4: Emission system
  console.log("\n⏱️ Emission System:");
  const emissionInfo = await atc.getEmissionInfo();
  console.log("Current Phase:", emissionInfo.currentPhase.toString());
  console.log("Daily Emission:", ethers.formatEther(emissionInfo.currentDailyEmission), "ATC");
  
  // Test 5: Liquidity info
  console.log("\n💧 Liquidity System:");
  const liquidityInfo = await atc.getLiquidityInfo();
  console.log("Pending Liquidity:", ethers.formatEther(liquidityInfo.atcPendingLiquidity), "ATC");
  console.log("Total Added:", ethers.formatEther(liquidityInfo.totalLiquidityAddedSoFar), "ATC");
  
  console.log("\n✅ All live contract tests completed successfully!");
  console.log("🌐 View on BSCScan: https://testnet.bscscan.com/address/" + CONTRACT_ADDRESS);
}

main().catch(console.error);
