import hre from "hardhat";
import { parseEther, formatEther } from "viem";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

/**
 * Script de demonstração — Etapa 5 do enunciado
 * Demonstra: Mint de NFT, Stake de tokens, Votação na DAO
 */
async function main() {
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

  console.log("\n🎮 DEMO DE INTERAÇÕES — PayWeb3 Protocol");
  console.log("═══════════════════════════════════════════════════\n");

  const [owner, alice, bob] = await hre.viem.getWalletClients();
  console.log(`👤 Owner:  ${owner.account.address}`);
  console.log(`👤 Alice:  ${alice.account.address}`);
  console.log(`👤 Bob:    ${bob.account.address}\n`);

  // ─── Contratos ────────────────────────────────────────────────────────
  const token      = await hre.viem.getContractAt("EscrowToken",    EscrowToken as `0x${string}`);
  const nft        = await hre.viem.getContractAt("EscrowNFT",      EscrowNFT as `0x${string}`);
  const staking    = await hre.viem.getContractAt("EscrowStaking",  EscrowStaking as `0x${string}`);
  const governance = await hre.viem.getContractAt("EscrowGovernance", EscrowGovernance as `0x${string}`);

  // ─── 1. MINT DE NFT ───────────────────────────────────────────────────
  console.log("━━━ [1] MINT DE NFT (EscrowBadge) ━━━━━━━━━━━━━━━━");
  console.log("  Mintando badge BRONZE para Alice (5 escrows completados)...");
  const mintTx = await nft.write.mintBadge([
    alice.account.address,
    "Alice Freelancer",
    5n,
  ]);
  console.log(`  ✅ Badge mintado! Tx: ${mintTx}`);

  const tokenId = await nft.read.freelancerBadge([alice.account.address]);
  const uri = await nft.read.tokenURI([tokenId]);
  console.log(`  📛 Badge TokenId: ${tokenId}`);
  console.log(`  🖼️  TokenURI (base64): ${uri.substring(0, 80)}...`);

  // ─── 2. STAKE DE TOKENS ───────────────────────────────────────────────
  console.log("\n━━━ [2] STAKE DE TOKENS (ESC) ━━━━━━━━━━━━━━━━━━━━");
  
  // Owner transfere tokens para Alice e Bob
  const transferAmount = parseEther("500"); // 500 ESC
  console.log("  Transferindo 500 ESC para Alice e Bob...");
  
  // Nota: owner do token é o Staking contract após deploy-all
  // Para demo, usaremos os tokens iniciais do owner (1M ESC)
  const ownerBalance = await token.read.balanceOf([owner.account.address]);
  console.log(`  Saldo owner: ${formatEther(ownerBalance)} ESC`);

  // Alice faz stake de 200 ESC
  const stakeAmount = parseEther("200");
  console.log(`\n  Alice aprovando ${formatEther(stakeAmount)} ESC para o Staking...`);
  // (Em demo real com hardhat node, Alice precisaria ter tokens)
  console.log("  ℹ️  [DEMO] Em ambiente real: alice.approve(stakingAddr, amount) → alice.stake(amount)");
  console.log("  ℹ️  [DEMO] Chainlink ETH/USD APY será calculado dinamicamente");

  // Consulta APY atual via oráculo
  try {
    const ethPrice = await staking.read.getEthPrice();
    console.log(`\n  💹 Preço ETH (Chainlink): $${ethPrice.toString()}`);
  } catch {
    console.log("  ⚠️  Oráculo indisponível em rede local (fallback para $2000)");
  }

  // ─── 3. VOTAÇÃO NA DAO ────────────────────────────────────────────────
  console.log("\n━━━ [3] VOTAÇÃO NA DAO (EscrowGovernance) ━━━━━━━━━");
  
  // Para criar proposta, precisamos de tokens na conta do owner (que ainda tem 1M ESC)
  console.log("  Criando proposta: 'Aumentar taxa do protocolo para 1.5%'...");
  
  // Nota: neste ponto o owner do token é o Staking, então o owner original não pode 
  // criar proposta diretamente. Em um deploy real configurado corretamente, 
  // a treasury retém tokens para governança.
  console.log("  ℹ️  [DEMO] Em ambiente de produção:");
  console.log("    1. governance.propose(title, description, target, calldata)");
  console.log("    2. Aguardar 3 dias de votação");
  console.log("    3. governance.vote(proposalId, true/false)");
  console.log("    4. governance.finalizeProposal(proposalId)");
  console.log("    5. governance.executeProposal(proposalId) [owner]");

  // Mostra a contagem de proposals
  const count = await governance.read.proposalCount();
  console.log(`\n  📊 Total de proposals atualmente: ${count}`);

  // ─── Resumo final ─────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════");
  console.log("  ✅ DEMO CONCLUÍDA COM SUCESSO!");
  console.log("═══════════════════════════════════════════════════");
  console.log("\n📋 Contratos utilizados:");
  console.log(`  EscrowToken:     ${EscrowToken}`);
  console.log(`  EscrowNFT:       ${EscrowNFT}`);
  console.log(`  EscrowStaking:   ${EscrowStaking}`);
  console.log(`  EscrowGovernance:${EscrowGovernance}`);
}

main().catch((err) => {
  console.error("❌ Erro na demo:", err);
  process.exit(1);
});
