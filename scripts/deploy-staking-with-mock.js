const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying EscrowStaking with Mock Oracle...");

  const [deployer] = await hre.ethers.getSigners();
  console.log(`Deployer: ${deployer.address}`);

  // Deploy Mock Oracle
  const MockV3Aggregator = await hre.ethers.getContractFactory("MockV3Aggregator");
  const mockOracle = await MockV3Aggregator.deploy(8, hre.ethers.parseUnits("2000", 8));
  await mockOracle.waitForDeployment();
  const mockOracleAddress = await mockOracle.getAddress();
  console.log(`✅ Mock Oracle deployed to: ${mockOracleAddress}`);

  // Token address
  const tokenAddress = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";

  // Deploy Staking com o mock oracle
  const EscrowStaking = await hre.ethers.getContractFactory("EscrowStaking");
  const staking = await EscrowStaking.deploy(tokenAddress, mockOracleAddress, deployer.address);
  await staking.waitForDeployment();
  const stakingAddress = await staking.getAddress();

  console.log(`✅ New EscrowStaking deployed to: ${stakingAddress}`);
  console.log(`\n📝 Atualize seu .env.local:`);
  console.log(`NEXT_PUBLIC_STAKING_ADDRESS=${stakingAddress}`);
  console.log(`NEXT_PUBLIC_TOKEN_ADDRESS=${tokenAddress}`);

  // Mint tokens for testing
  const EscrowToken = await hre.ethers.getContractFactory("EscrowToken");
  const token = await EscrowToken.attach(tokenAddress);

  const freelancer = "0x8626f6940e2eb28930efb4cef49b2d1f2c9c1199";
  await token.mint(freelancer, hre.ethers.parseEther("1000"));
  console.log(`✅ Minted 1000 ESC to freelancer: ${freelancer}`);

  console.log("\n🎉 Done! Update your frontend .env.local with the new STAKING_ADDRESS");
}

main().catch(console.error);