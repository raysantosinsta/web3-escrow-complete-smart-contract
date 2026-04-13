import hre from "hardhat";
import "@nomicfoundation/hardhat-toolbox-viem";

async function main() {
  console.log("🚀 Iniciando deploy do contrato Escrow na Polygon Amoy usando Viem...");

  const viem = (hre as any).viem;
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("👤 Deployer account:", deployer.account.address);
  
  const balance = await publicClient.getBalance({ 
    address: deployer.account.address 
  });
  console.log("💰 Balance:", balance.toString());

  const escrow = await viem.deployContract("Escrow");

  console.log("✅ Escrow implantado em:", escrow.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
