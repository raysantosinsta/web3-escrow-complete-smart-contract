# 📜 PayWeb3 Smart Contracts — Infraestrutura On-chain

> **Suíte de contratos inteligentes para liquidação financeira, staking algorítmico e governança descentralizada na rede Ethereum Sepolia.**

---

## 📖 Visão Geral

Os contratos do **PayWeb3** formam o esqueleto de um protocolo de confiança programável. A arquitetura foi desenhada para ser modular, separando as preocupações de pagamento (Escrow), incentivos (Staking), reputação (NFT) e decisões (DAO), utilizando padrões da indústria como **OpenZeppelin** e **Chainlink**.

---

## ⚠️ O Problema

1. **Risco de Contraparte:** Em negociações P2P, o risco de uma das partes não cumprir o acordo é alto sem um intermediário confiável.
2. **Recompensas Estáticas:** Sistemas de staking com rendimento fixo ignoram a volatilidade do mercado, tornando-se insustentáveis ou pouco atraentes.
3. **Falta de Histórico Verificável:** No mundo freelance, é difícil provar competência de forma imutável e descentralizada.

## ✅ A Solução (Core Logic)

1. **Smart Escrow (Escrow.sol):** Atua como um "terceiro fiel" digital que retém fundos em garantia e só os libera mediante prova de execução ou consenso via assinaturas criptográficas.
2. **Oracle-Based Staking (EscrowStaking.sol):** Utiliza **Oráculos da Chainlink** para ajustar o APY das recompensas baseando-se no preço do par ETH/USD, protegendo o valor real dos rendimentos.
3. **On-chain Reputation (EscrowNFT.sol):** Badges Soulbound (não transferíveis) emitidos automaticamente para freelancers com base no volume de transações concluídas com sucesso.

---

## 🛠️ Detalhes da Implementação

### 1. Escrow & Pagamentos (`Escrow.sol`)

- **Segurança:** Proteção contra ataques de Reentrância e Overflow/Underflow (Solidity 0.8+).
- **Taxas:** Lógica integrada de cobrança de taxas de protocolo (Basis Points) enviadas automaticamente para a carteira de tesouraria.
- **Estados:** Implementação de máquina de estados robusta para rastrear cada fase do pagamento.

### 2. Staking Algorítmico (`EscrowStaking.sol`)

- **Integração Chainlink:** Consumo do `AggregatorV3Interface` para busca de preços em tempo real.
- **Fórmula de Recompensa:** Cálculo de rendimentos baseado no tempo decorrido (block.timestamp) e peso do stake, com multiplicador dinâmico via Oráculo.

### 3. Governança DAO (`EscrowGovernance.sol`)

- **Quórum e Propostas:** Sistema de votação por quórum mínimo e maioria simples.
- **Poder de Voto:** Utiliza o snapshot do saldo do token ESC para definir o peso de influência de cada holder.

---

## 🛠️ Stack Tecnológica

- **Linguagem:** Solidity ^0.8.20.
- **Framework:** Hardhat.
- **Bibliotecas:** OpenZeppelin (ERC20, ERC721, Ownable, ReentrancyGuard).
- **Oráculos:** Chainlink Price Feeds.
- **Testes:** Viem / Chai para validação de cenários de sucesso e falha.

---

## 📦 Como Realizar o Deploy

1. **Instale as dependências:**

   ```bash
   npm install
   ```

2. **Configure o arquivo `.env`:**

   ```env
   SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/..."
   PRIVATE_KEY="sua_chave_privada"
   ```

3. **Compile os contratos:**

   ```bash
   npx hardhat compile
   ```

4. **Execute o Script de Deploy:**
   ```bash
   npx hardhat run scripts/deploy-all.ts --network sepolia
   ```

---

## 🛡️ Considerações de Segurança

- **Access Control:** Uso rigoroso de modificadores `onlyOwner` e verificações de endereço.
- **Pull over Push:** Padrão de saque de recompensas e pagamentos para evitar travamento de contratos por gas limit ou ataques de negação de serviço.
- **Modularidade:** Contratos independentes para facilitar auditorias e upgrades futuros via proxies (opcional).

---

**Desenvolvido por: Highlander**
_Projeto Final - Smart Contracts e Blockchain._
