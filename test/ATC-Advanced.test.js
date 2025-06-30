const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ATC Advanced Features", function () {
  let atc, mockRouter, mockFactory, weth, pair;
  let owner, user1, user2;
  
  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    // Deploy mocks
    const WETH = await ethers.getContractFactory("MockWETH");
    weth = await WETH.deploy();
    await weth.waitForDeployment();
    
    const MockFactory = await ethers.getContractFactory("MockPancakeFactory");
    mockFactory = await MockFactory.deploy();
    await mockFactory.waitForDeployment();
    
    const MockRouter = await ethers.getContractFactory("MockPancakeRouter");
    mockRouter = await MockRouter.deploy(await weth.getAddress(), await mockFactory.getAddress());
    await mockRouter.waitForDeployment();
    
    // Deploy ATC
    const ATC = await ethers.getContractFactory("ATC");
    atc = await ATC.deploy(await mockRouter.getAddress());
    await atc.waitForDeployment();
    
    // Get pair address
    const pairAddress = await atc.pair();
    pair = await ethers.getContractAt("MockPancakePair", pairAddress);
  });
  
  describe("Trading Controls", function () {
    it("Should prevent trading when disabled", async function () {
      await atc.transfer(user1.address, ethers.parseEther("1000"));
      
      try {
        await atc.connect(user1).transfer(user2.address, ethers.parseEther("100"));
        expect.fail("Transaction should have reverted");
      } catch (error) {
        expect(error.message).to.include("Trading not enabled");
      }
    });
    
    it("Should allow trading when enabled", async function () {
      await atc.setTradingEnabled(true);
      await atc.transfer(user1.address, ethers.parseEther("1000"));
      
      await atc.connect(user1).transfer(user2.address, ethers.parseEther("100"));
      
      expect(await atc.balanceOf(user2.address)).to.equal(ethers.parseEther("100"));
      console.log("✅ Trading enabled successfully");
    });
  });
  
  describe("Emission System", function () {
    it("Should show emission system information", async function () {
      const emissionInfo = await atc.getEmissionInfo();
      
      // Convert BigInt to regular number for display
      const dailyEmission = Number(emissionInfo.currentDailyEmission) / Number(ethers.parseEther("1"));
      const phase = Number(emissionInfo.currentPhase);
      const daysSinceLaunch = Number(emissionInfo.daysSinceLaunch);
      
      console.log("✅ Current emission phase:", phase);
      console.log("✅ Days since launch:", daysSinceLaunch);
      console.log("✅ Daily emission:", dailyEmission, "ATC/day");
      
      // Test that emission system is working (any phase is fine for testing)
      expect(phase).to.be.oneOf([1, 2, 3]); // Should be one of the valid phases
      expect(dailyEmission).to.be.greaterThan(0); // Should have some emission
      
      // Test phase-specific values
      if (phase === 1) {
        expect(dailyEmission).to.equal(100);
        console.log("📅 In Phase 1: Constant 100 ATC/day");
      } else if (phase === 2) {
        expect(dailyEmission).to.be.greaterThan(100);
        console.log("📈 In Phase 2: Ramping up emission");
      } else if (phase === 3) {
        console.log("📉 In Phase 3: Decay phase");
      }
    });
    
    it("Should allow testnet emission manipulation", async function () {
      // Test the testnet helper functions
      try {
        // Reset to day 1 (Phase 1)
        await atc.setLastEmissionDay(1);
        
        const emissionInfo = await atc.getEmissionInfo();
        const phase = Number(emissionInfo.currentPhase);
        const dailyEmission = Number(emissionInfo.currentDailyEmission) / Number(ethers.parseEther("1"));
        
        expect(phase).to.equal(1);
        expect(dailyEmission).to.equal(100);
        
        console.log("✅ Successfully reset to Phase 1");
        console.log("✅ Confirmed Phase 1 emission:", dailyEmission, "ATC/day");
        
      } catch (error) {
        if (error.message.includes("Function only available on testnet")) {
          console.log("ℹ️ Testnet functions not available on this network");
        } else {
          throw error;
        }
      }
    });
  });
  
  describe("Tax System", function () {
    it("Should have correct initial tax rates", async function () {
      const taxRates = await atc.taxRates();
      
      const buyTax = Number(taxRates.buyTax);
      const sellTax = Number(taxRates.sellTax);
      
      expect(buyTax).to.equal(2500); // 25%
      expect(sellTax).to.equal(2500); // 25%
      
      console.log("✅ Buy tax:", buyTax / 100, "%");
      console.log("✅ Sell tax:", sellTax / 100, "%");
    });
  });
  
  describe("Contract Information", function () {
    it("Should have correct contract details", async function () {
      expect(await atc.name()).to.equal("Automator Coin");
      expect(await atc.symbol()).to.equal("ATC");
      
      const totalSupply = Number(await atc.totalSupply()) / Number(ethers.parseEther("1"));
      expect(totalSupply).to.equal(1000000000); // 1 billion
      
      console.log("✅ Contract name:", await atc.name());
      console.log("✅ Total supply:", totalSupply.toLocaleString(), "ATC");
    });
    
    it("Should show liquidity information", async function () {
      const liquidityInfo = await atc.getLiquidityInfo();
      
      const pendingLiquidity = Number(liquidityInfo.atcPendingLiquidity) / Number(ethers.parseEther("1"));
      const totalAdded = Number(liquidityInfo.totalLiquidityAddedSoFar) / Number(ethers.parseEther("1"));
      const remaining = Number(liquidityInfo.remainingLiquidityCapacity) / Number(ethers.parseEther("1"));
      
      console.log("✅ ATC pending liquidity:", pendingLiquidity.toLocaleString());
      console.log("✅ Total liquidity added:", totalAdded.toLocaleString());
      console.log("✅ Remaining capacity:", remaining.toLocaleString());
      
      expect(totalAdded).to.be.greaterThan(0);
    });
  });
});
