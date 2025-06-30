const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ATC Complete Test Suite", function () {
  let atc, mockRouter, mockFactory, weth, pair;
  let owner, user1, user2;
  
  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    // Deploy all contracts
    const WETH = await ethers.getContractFactory("MockWETH");
    weth = await WETH.deploy();
    await weth.waitForDeployment();
    
    const MockFactory = await ethers.getContractFactory("MockPancakeFactory");
    mockFactory = await MockFactory.deploy();
    await mockFactory.waitForDeployment();
    
    const MockRouter = await ethers.getContractFactory("MockPancakeRouter");
    mockRouter = await MockRouter.deploy(await weth.getAddress(), await mockFactory.getAddress());
    await mockRouter.waitForDeployment();
    
    const ATC = await ethers.getContractFactory("ATC");
    atc = await ATC.deploy(await mockRouter.getAddress());
    await atc.waitForDeployment();
    
    const pairAddress = await atc.pair();
    pair = await ethers.getContractAt("MockPancakePair", pairAddress);
  });
  
  describe("🚀 Deployment & Basic Functionality", function () {
    it("Should deploy with correct parameters", async function () {
      expect(await atc.name()).to.equal("Automator Coin");
      expect(await atc.symbol()).to.equal("ATC");
      expect(await atc.owner()).to.equal(owner.address);
      
      const totalSupply = Number(await atc.totalSupply()) / Number(ethers.parseEther("1"));
      expect(totalSupply).to.equal(1000000000);
      
      console.log("✅ ATC Contract Successfully Deployed");
      console.log("📊 Total Supply:", totalSupply.toLocaleString(), "ATC");
    });
  });
  
  describe("🔒 Access Control & Security", function () {
    it("Should handle trading permissions correctly", async function () {
      // Trading disabled by default
      await atc.transfer(user1.address, ethers.parseEther("1000"));
      
      try {
        await atc.connect(user1).transfer(user2.address, ethers.parseEther("100"));
        expect.fail("Should have reverted");
      } catch (error) {
        expect(error.message).to.include("Trading not enabled");
      }
      
      // Enable trading
      await atc.setTradingEnabled(true);
      await atc.connect(user1).transfer(user2.address, ethers.parseEther("100"));
      expect(await atc.balanceOf(user2.address)).to.equal(ethers.parseEther("100"));
      
      console.log("✅ Trading controls working correctly");
    });
    
    it("Should enforce anti-whale protection", async function () {
      await atc.setTradingEnabled(true);
      
      const maxTxAmount = await atc.MAX_TX_AMOUNT();
      const largeAmount = maxTxAmount + BigInt(1);
      
      await atc.transfer(user1.address, largeAmount);
      
      try {
        await atc.connect(user1).transfer(user2.address, largeAmount);
        expect.fail("Should have reverted");
      } catch (error) {
        expect(error.message).to.include("Transfer exceeds max transaction");
      }
      
      console.log("✅ Anti-whale protection active");
    });
  });
  
  describe("💰 Tax System", function () {
    it("Should have correct tax configuration", async function () {
      const taxRates = await atc.taxRates();
      
      expect(Number(taxRates.buyTax)).to.equal(2500);
      expect(Number(taxRates.sellTax)).to.equal(2500);
      expect(Number(taxRates.liquidityTax)).to.equal(500);
      expect(Number(taxRates.devTax)).to.equal(1000);
      expect(Number(taxRates.artistTax)).to.equal(500);
      expect(Number(taxRates.marketingTax)).to.equal(500);
      
      console.log("✅ Tax rates configured correctly:");
      console.log("   📈 Buy/Sell Tax: 25%");
      console.log("   💧 Liquidity: 5%, 👨‍💻 Dev: 10%, 🎨 Artist: 5%, 📢 Marketing: 5%");
    });
  });
  
  describe("⏱️ Emission System", function () {
    it("Should show current emission status", async function () {
      const emissionInfo = await atc.getEmissionInfo();
      
      const phase = Number(emissionInfo.currentPhase);
      const dailyEmission = Number(emissionInfo.currentDailyEmission) / Number(ethers.parseEther("1"));
      const daysSinceLaunch = Number(emissionInfo.daysSinceLaunch);
      
      expect(phase).to.be.oneOf([1, 2, 3]);
      expect(dailyEmission).to.be.greaterThan(0);
      
      console.log("✅ Emission System Status:");
      console.log(`   📅 Current Phase: ${phase}`);
      console.log(`   🗓️ Days Since Launch: ${daysSinceLaunch.toLocaleString()}`);
      console.log(`   💎 Daily Emission: ${dailyEmission} ATC`);
    });
  });
  
  describe("💧 Liquidity System", function () {
    it("Should show liquidity status", async function () {
      const liquidityInfo = await atc.getLiquidityInfo();
      
      const pending = Number(liquidityInfo.atcPendingLiquidity) / Number(ethers.parseEther("1"));
      const totalAdded = Number(liquidityInfo.totalLiquidityAddedSoFar) / Number(ethers.parseEther("1"));
      const remaining = Number(liquidityInfo.remainingLiquidityCapacity) / Number(ethers.parseEther("1"));
      
      expect(totalAdded).to.be.greaterThan(0);
      
      console.log("✅ Liquidity System Status:");
      console.log(`   🏦 Total Added: ${totalAdded.toLocaleString()} ATC`);
      console.log(`   ⏳ Pending: ${pending.toLocaleString()} ATC`);
      console.log(`   📊 Remaining Capacity: ${remaining.toLocaleString()} ATC`);
    });
  });
  
  describe("🔥 Burn Functionality", function () {
    it("Should allow token burning", async function () {
      await atc.transfer(user1.address, ethers.parseEther("1000"));
      
      const initialSupply = await atc.totalSupply();
      const burnAmount = ethers.parseEther("100");
      
      await atc.connect(user1).burn(burnAmount);
      
      const finalSupply = await atc.totalSupply();
      expect(finalSupply).to.equal(initialSupply - burnAmount);
      
      console.log("✅ Token burning works correctly");
    });
  });
});
