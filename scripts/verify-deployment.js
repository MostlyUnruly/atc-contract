const { ethers } = require("hardhat");

async function main() {
  const contractAddress = process.env.CONTRACT_ADDRESS;
  if (!contractAddress) {
    throw new Error("CONTRACT_ADDRESS environment variable not set");
  }

  console.log("Verifying deployment at:", contractAddress);
  
  const atc = await ethers.getContractAt("ATC", contractAddress);
  
  // Basic verification
  const name = await atc.name();
  const symbol = await atc.symbol();
  const totalSupply = await atc.totalSupply();
  
  console.log("✅ Contract verified:");
  console.log("Name:", name);
  console.log("Symbol:", symbol);
  console.log("Total Supply:", ethers.formatEther(totalSupply));
  
  // Check if trading is enabled
  const tradingEnabled = await atc.tradingEnabled();
  console.log("Trading enabled:", tradingEnabled);
  
  // Get emission info
  const emissionInfo = await atc.getEmissionInfo();
  console.log("Current phase:", emissionInfo.currentPhase.toString());
  console.log("Daily emission:", ethers.formatEther(emissionInfo.currentDailyEmission));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
