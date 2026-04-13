import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("EscrowModule", (m) => {
  const escrow = m.contract("Escrow");


  const seller = m.getAccount(1);
  const buyer = m.getAccount(0);
  m.call(escrow, "pay", [seller, buyer, true], { value: 1_000_000_000_000_000_000n });

  return { escrow };
});
