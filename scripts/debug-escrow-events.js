const hre = require("hardhat");

async function main() {
  const escrowAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const escrow = await hre.ethers.getContractAt("Escrow", escrowAddress);

  // Buscar eventos PaymentCreated
  const filter = escrow.filters.PaymentCreated();
  const events = await escrow.queryFilter(filter);

  console.log(`\n📊 Encontrados ${events.length} eventos PaymentCreated:\n`);

  for (const event of events) {
    console.log(`Evento #${event.args.id}:`);
    console.log(`  - Buyer: ${event.args.buyer}`);
    console.log(`  - Seller: ${event.args.seller}`);
    console.log(`  - Amount: ${hre.ethers.formatEther(event.args.amount)} MATIC`);
    console.log(`  - Fee: ${hre.ethers.formatEther(event.args.fee)} MATIC`);
    console.log(`  - TxHash: ${event.transactionHash}`);
    console.log(`  - Block: ${event.blockNumber}\n`);
  }
}

main().catch(console.error);