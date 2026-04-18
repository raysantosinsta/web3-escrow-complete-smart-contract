import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("EscrowSystem", (m) => {
  const owner = m.getAccount(0);

  // 🔗 Substitua por um endereço válido na Amoy (mock ou real)
  const priceFeed = "0x0000000000000000000000000000000000000000";

  // 1. Token
  const token = m.contract("EscrowToken", [owner]);

  // 2. NFT
  const nft = m.contract("EscrowNFT", [owner]);

  // 3. Escrow (sem params)
  const escrow = m.contract("Escrow");

  // 4. Staking
  const staking = m.contract("EscrowStaking", [
    token,
    priceFeed,
    owner,
  ]);

  // 5. Governança
  const governance = m.contract("EscrowGovernance", [
    token,
    owner,
  ]);

  return {
    token,
    nft,
    escrow,
    staking,
    governance,
  };
});