const { ethers } = require("hardhat");

async function main() {
  // Your deployed contract address
  const CONTRACT_ADDRESS = "0xd71509cDFd55a30658D7569aBdAC6737638e5eda";
  
  const [owner] = await ethers.getSigners();
  console.log("Interacting with contract as:", owner.address);
  
  // Get the deployed contract
  const atc = await ethers.getContractAt("ATC", CONTRACT_ADDRESS);
  
  console.log("\n📊 Current Contract Status:");
  console.log("Trading enabled:", await atc.tradingEnabled());
  console.log("Owner balance:", ethers.formatEther(await atc.balanceOf(owner.address)), "ATC");
  
  // Enable trading
  console.log("\n🚀 Enabling trading...");
  const tx = await atc.setTradingEnabled(true);
  await tx.wait();
  
  console.log("✅ Trading enabled!");
  console.log("Trading status:", await atc.tradingEnabled());
  
  console.log("\n🎉 Your ATC token is now tradeable on BSC Testnet!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
