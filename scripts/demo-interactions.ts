import { createWalletClient, createPublicClient, http, parseEther, formatEther, getContract } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia, hardhat } from "viem/chains";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import hre from "hardhat";

async function main() {
  const networkArgIndex = process.argv.indexOf("--network");
  const networkName = networkArgIndex !== -1 ? process.argv[networkArgIndex + 1] : "localhost";

  const __dirname = dirname(fileURLToPath(import.meta.url));
  const addressesPath = join(__dirname, "..", "deployed-addresses.json");

  let addresses: Record<string, Record<string, string>>;
  try {
    addresses = JSON.parse(readFileSync(addressesPath, "utf-8"));
  } catch {
    console.error("❌ Execute o deploy-all.ts primeiro para gerar deployed-addresses.json");
    process.exit(1);
  }

  const { EscrowToken, EscrowNFT, EscrowStaking, EscrowGovernance } = addresses.contracts;

  console.log(`\n🎮 DEMO DE INTERAÇÕES — Rede: ${networkName}`);
  console.log("═══════════════════════════════════════════════════\n");

  const PRIVATE_KEY = (process.env.PRIVATE_KEY || "0xc9db5c9ee35683e48d4ed3f4e2158120271398e09545f891147a259e1804702d") as `0x${string}`;
  const account = privateKeyToAccount(PRIVATE_KEY);
  const chain = networkName === "sepolia" ? sepolia : hardhat;
  const transport = http(networkName === "sepolia" ? process.env.SEPOLIA_RPC_URL : "http://127.0.0.1:8545");

  const walletClient = createWalletClient({ account, chain, transport });
  const publicClient = createPublicClient({ chain, transport });

  console.log(`👤 Executor: ${account.address}\n`);

  // Artifacts (ABIs)
  const getAbi = (name: string) => {
    const path = join(process.cwd(), "artifacts", "contracts", `${name}.sol`, `${name}.json`);
    return JSON.parse(readFileSync(path, "utf8")).abi;
  };

  // ─── Contratos ────────────────────────────────────────────────────────
  const token = getContract({ address: EscrowToken as `0x${string}`, abi: getAbi("EscrowToken"), client: { wallet: walletClient, public: publicClient } });
  const nft = getContract({ address: EscrowNFT as `0x${string}`, abi: getAbi("EscrowNFT"), client: { wallet: walletClient, public: publicClient } });
  const staking = getContract({ address: EscrowStaking as `0x${string}`, abi: getAbi("EscrowStaking"), client: { wallet: walletClient, public: publicClient } });
  const governance = getContract({ address: EscrowGovernance as `0x${string}`, abi: getAbi("EscrowGovernance"), client: { wallet: walletClient, public: publicClient } });

  // ─── 1. MINT DE NFT ───────────────────────────────────────────────────
  console.log(`  Mintando badge BRONZE para ${account.address} (5 escrows completados)...`);

  const alreadyHasBadge = await nft.read.hasBadge([account.address]) as boolean;

  if (!alreadyHasBadge) {
    const mintTx = await nft.write.mintBadge([
      account.address,
      "Freelancer VIP",
      5n,
    ]);
    console.log(`  ✅ Transação enviada! Aguardando confirmação...`);
    await publicClient.waitForTransactionReceipt({ hash: mintTx });
    console.log(`  ✅ Badge mintado com sucesso! Tx: ${mintTx}`);
  } else {
    console.log(`  ℹ️  Você já possui um badge! Pulando o mint...`);
  }

  const tokenId = await nft.read.freelancerBadge([account.address]) as any;
  const uri = await nft.read.tokenURI([tokenId]) as string;
  console.log(`  📛 Badge TokenId: ${tokenId}`);
  console.log(`  🖼️  TokenURI (base64): ${uri.substring(0, 80)}...`);

  // ─── 2. STAKE DE TOKENS ───────────────────────────────────────────────
  console.log("\n━━━ [2] STAKE DE TOKENS (ESC) ━━━━━━━━━━━━━━━━━━━━");

  const balance = await token.read.balanceOf([account.address]) as any;
  console.log(`  Seu saldo: ${formatEther(balance)} ESC`);

  const ethPrice = await staking.read.getEthPrice() as any;
  console.log(`  💹 Preço ETH (Chainlink): $${ethPrice.toString()}`);

  // ─── 3. VOTAÇÃO NA DAO ────────────────────────────────────────────────
  console.log("\n━━━ [3] VOTAÇÃO NA DAO (EscrowGovernance) ━━━━━━━━━");

  console.log("  ℹ️  [INFO] Em ambiente de produção, os tokens ESC permitem:");
  console.log("    1. Criar propostas de governança");
  console.log("    2. Votar em mudanças de taxas");

  const count = await governance.read.proposalCount() as any;
  console.log(`  📊 Total de propostas na DAO: ${count}`);

  // ─── Resumo final ─────────────────────────────────────────────────────
  console.log("📋 Contratos utilizados:");
  console.log(`  EscrowToken:      ${EscrowToken}`);
  console.log(`  EscrowNFT:        ${EscrowNFT}`);
  console.log(`  EscrowStaking:    ${EscrowStaking}`);
  console.log(`  EscrowGovernance: ${EscrowGovernance}`);

  console.log("\n═══════════════════════════════════════════════════");
  console.log("  ✅ DEMO CONCLUÍDA COM SUCESSO!");
  console.log("═══════════════════════════════════════════════════\n");
}

main().catch((err) => {
  console.error("❌ Erro na demo:", err);
  process.exit(1);
});
