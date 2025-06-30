const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);
  
  // Get balance
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "BNB");
  
  // For BSC Testnet, we'll use PancakeSwap testnet router
  const ROUTER_ADDRESS = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1";
  
  console.log("Using PancakeSwap Router:", ROUTER_ADDRESS);
  
  // Deploy ATC contract
  console.log("Deploying ATC contract...");
  const ATC = await ethers.getContractFactory("ATC");
  const atc = await ATC.deploy(ROUTER_ADDRESS);
  
  await atc.waitForDeployment();
  
  const contractAddress = await atc.getAddress();
  console.log("🎉 ATC deployed to:", contractAddress);
  console.log("Router address:", await atc.router());
  console.log("Pair address:", await atc.pair());
  console.log("WETH address:", await atc.weth());
  
  // Verify deployment
  console.log("\n✅ Verifying deployment...");
  console.log("Total supply:", ethers.formatEther(await atc.totalSupply()));
  console.log("Owner balance:", ethers.formatEther(await atc.balanceOf(deployer.address)));
  console.log("Trading enabled:", await atc.tradingEnabled());
  
  console.log("\n🔗 View on BSCScan Testnet:");
  console.log(`https://testnet.bscscan.com/address/${contractAddress}`);
  
  console.log("\n🎉 Deployment Complete!");
  
  return atc;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
