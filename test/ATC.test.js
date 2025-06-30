const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ATC Token", function () {
  let atc, mockRouter, mockFactory, weth;
  let owner, user1;
  
  beforeEach(async function () {
    [owner, user1] = await ethers.getSigners();
    
    // Deploy WETH mock
    const WETH = await ethers.getContractFactory("MockWETH");
    weth = await WETH.deploy();
    await weth.waitForDeployment();
    console.log("WETH deployed to:", await weth.getAddress());
    
    // Deploy Factory mock
    const MockFactory = await ethers.getContractFactory("MockPancakeFactory");
    mockFactory = await MockFactory.deploy();
    await mockFactory.waitForDeployment();
    console.log("Factory deployed to:", await mockFactory.getAddress());
    
    // Deploy Router mock
    const MockRouter = await ethers.getContractFactory("MockPancakeRouter");
    mockRouter = await MockRouter.deploy(await weth.getAddress(), await mockFactory.getAddress());
    await mockRouter.waitForDeployment();
    console.log("Router deployed to:", await mockRouter.getAddress());
    
    // Deploy ATC contract
    const ATC = await ethers.getContractFactory("ATC");
    atc = await ATC.deploy(await mockRouter.getAddress());
    await atc.waitForDeployment();
    console.log("ATC deployed to:", await atc.getAddress());
  });
  
  it("Should deploy successfully", async function () {
    expect(await atc.name()).to.equal("Automator Coin");
    expect(await atc.symbol()).to.equal("ATC");
    expect(await atc.owner()).to.equal(owner.address);
    console.log("✅ ATC deployed successfully!");
  });
  
  it("Should have correct initial supply", async function () {
    const totalSupply = await atc.totalSupply();
    const ownerBalance = await atc.balanceOf(owner.address);
    expect(totalSupply).to.equal(ownerBalance);
    console.log("✅ Total supply:", ethers.formatEther(totalSupply));
  });
});
