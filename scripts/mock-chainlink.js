const hre = require("hardhat");

async function main() {
  console.log("📡 Deploying Chainlink Mock Oracle...");

  // Deploy do Mock Oracle
  const MockV3Aggregator = await hre.ethers.getContractFactory("MockV3Aggregator");
  const decimals = 8;
  const initialAnswer = hre.ethers.parseUnits("2000", decimals); // $2000 com 8 decimais
  const mockOracle = await MockV3Aggregator.deploy(decimals, initialAnswer);
  await mockOracle.waitForDeployment();

  const mockOracleAddress = await mockOracle.getAddress();
  console.log(`✅ Mock Oracle deployed to: ${mockOracleAddress}`);

  // Atualizar o contrato de Staking com o novo oracle
  const stakingAddress = "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9";
  const EscrowStaking = await hre.ethers.getContractFactory("EscrowStaking");
  const staking = await EscrowStaking.attach(stakingAddress);

  // Verificar se precisa atualizar (se o contrato já tiver oracle, vamos trocar)
  console.log("🔧 Atualizando contrato de Staking com o novo Oracle...");

  // Como o oracle é imutável no construtor, precisamos criar um novo contrato
  // ou usar o que já está deployado. Vamos verificar o oracle atual
  const currentOracle = await staking.ethUsdPriceFeed();
  console.log(`Oracle atual: ${currentOracle}`);

  console.log("\n🎯 Para resolver permanentemente, redeploy o contrato Staking com o mock oracle:");
  console.log(`npx hardhat run scripts/deploy-staking-with-mock.js --network localhost`);
}

main().catch(console.error);