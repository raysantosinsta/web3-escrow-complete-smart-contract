# PayWeb3 Protocol — MVP Descentralizado

> Protocolo descentralizado completo: Escrow seguro + Token ERC-20 + NFT ERC-721 + Staking com Chainlink + DAO de Governança

---

## 🏗️ Arquitetura do Protocolo

```
┌─────────────────────────────────────────────────────┐
│                  PROTOCOLO PAYWEB3                  │
├───────────────┬───────────────┬─────────────────────┤
│  EscrowToken  │  EscrowNFT    │    Escrow.sol        │
│  (ERC-20)     │  (ERC-721)    │  Custódia segura     │
│  Token ESC    │  Badge NFT    │  Máquina de estados  │
└──────┬────────┴───────┬───────┴──────────┬──────────┘
       │                │                  │
       ▼                ▼                  ▼
┌─────────────┐  ┌─────────────┐  ┌──────────────────┐
│  Staking    │  │ Governance  │  │  Chainlink        │
│  Contract   │  │  DAO        │  │  ETH/USD Price   │
│  APY dinâm. │  │  Votação    │  │  Feed (Sepolia)   │
└─────────────┘  └─────────────┘  └──────────────────┘
```

---

## 📋 Contratos

| Contrato | Padrão | Descrição |
|---|---|---|
| `EscrowToken.sol` | ERC-20 | Token ESC — recompensas e governança |
| `EscrowNFT.sol` | ERC-721 | Badge on-chain para freelancers (SVG base64) |
| `EscrowStaking.sol` | Custom | Staking com APY dinâmico via Chainlink ETH/USD |
| `EscrowGovernance.sol` | DAO | Governança com votação ponderada por ESC |
| `Escrow.sol` | Custom | Custódia segura com máquina de estados |

---

## 🔗 Endereços de Deploy — Sepolia Testnet

> Preencher após executar o deploy

| Contrato | Endereço | Explorer |
|---|---|---|
| EscrowToken (ESC) | `0x...` | [Etherscan](https://sepolia.etherscan.io/address/0x...) |
| EscrowNFT (ESCBDG) | `0x...` | [Etherscan](https://sepolia.etherscan.io/address/0x...) |
| EscrowStaking | `0x...` | [Etherscan](https://sepolia.etherscan.io/address/0x...) |
| EscrowGovernance | `0x...` | [Etherscan](https://sepolia.etherscan.io/address/0x...) |
| Escrow | `0x...` | [Etherscan](https://sepolia.etherscan.io/address/0x...) |

**Chainlink ETH/USD Feed (Sepolia):** `0x694AA1769357215DE4FAC081bf1f309aDC325306`

---

## 🚀 Como Executar

### Pré-requisitos

- Node.js >= 18
- npm >= 9
- MetaMask com ETH na Sepolia ([Faucet](https://sepoliafaucet.com))

### 1. Instalar dependências

```bash
# Contratos
cd contracts && npm install

# Frontend
cd ../frontend && npm install

# Backend
cd ../backend && npm install
```

### 2. Configurar variáveis de ambiente

```bash
# Contratos — criar arquivo .env
# contracts/.env
SEPOLIA_RPC_URL=https://rpc.sepolia.org
SEPOLIA_PRIVATE_KEY=0xSUA_CHAVE_PRIVADA

# Frontend
cp frontend/.env.example frontend/.env.local
# Preencher endereços após o deploy
```

### 3. Compilar contratos

```bash
cd contracts
npx hardhat compile
```

### 4. Deploy em Sepolia

```bash
cd contracts
npx hardhat run scripts/deploy-all.ts --network sepolia
```

Os endereços serão salvos em `contracts/deployed-addresses.json`. Copie-os para o `frontend/.env.local`.

### 5. Executar script de demonstração

```bash
cd contracts
npx hardhat run scripts/demo-interactions.ts --network sepolia
```

### 6. Iniciar o frontend

```bash
cd frontend
npm run dev
# Acesse http://localhost:3000
```

---

## 🎮 Funcionalidades do Frontend

### Staking (`/staking`)
- Stake/Unstake de tokens ESC
- APY dinâmico baseado no preço ETH (Chainlink)
- Claim de recompensas em ESC
- Visualização do preço ETH em tempo real

### Governança (`/governance`)  
- Criação de propostas (mínimo 100 ESC)
- Votação ponderada por saldo de ESC
- Progresso de quórum em tempo real
- Lifecycle completo: Ativa → Aprovada/Rejeitada → Executada

---

## 🔐 Segurança

- ✅ `ReentrancyGuard` em todas as funções de transferência
- ✅ Padrão Checks-Effects-Interactions
- ✅ `Ownable` para controle de acesso
- ✅ Solidity ^0.8.x (overflow/underflow protegido nativamente)
- ✅ OpenZeppelin v5 (auditada e battle-tested)
- ✅ Integração Chainlink com fallback seguro

Ver relatório completo em [`AUDIT_REPORT.md`](./AUDIT_REPORT.md).

---

## 🔮 Integração Chainlink (Etapa 4)

- **Feed:** ETH/USD na Sepolia (`0x694AA1769357215DE4FAC081bf1f309aDC325306`)
- **Uso:** `EscrowStaking.sol` consulta o preço do ETH a cada interação de staking
- **Fórmula do APY:**
  ```
  APY_ajustado = 10% × (preço_ETH / $2.000)
  Cap máximo: 50% ao ano
  ```
- **Fallback:** Se o oráculo falhar ou ficar desatualizado (>1h), usa $2.000 como referência

---

## 📊 Diagrama de Fluxo de Staking

```
Usuário  →  approve(stakingAddr, amount)   →  EscrowToken
         →  stake(amount)                  →  EscrowStaking
                                              ├── Consulta ETH/USD (Chainlink)
                                              ├── Calcula APY dinâmico
                                              └── Acumula recompensas
         →  claimRewards()                 →  EscrowStaking
                                              └── mint(user, rewards)  →  EscrowToken
```

## 📊 Diagrama de Fluxo de Governança

```
Holder (≥100 ESC)  →  propose(title, desc)  →  EscrowGovernance
                                                └── Período: 3 dias
Qualquer holder    →  vote(id, true/false)   →  EscrowGovernance (ponderado por ESC)
Qualquer pessoa    →  finalizeProposal(id)   →  EscrowGovernance (após prazo)
Admin              →  executeProposal(id)    →  Contrato alvo (se aprovada)
```

---

## 📦 Estrutura do Projeto

```
web3-escrow-complete/
├── contracts/
│   ├── contracts/
│   │   ├── Escrow.sol           # Custódia (existente)
│   │   ├── EscrowToken.sol      # ERC-20 ESC
│   │   ├── EscrowNFT.sol        # ERC-721 Badge
│   │   ├── EscrowStaking.sol    # Staking + Chainlink
│   │   └── EscrowGovernance.sol # DAO
│   ├── scripts/
│   │   ├── deploy-all.ts        # Deploy de todos os contratos
│   │   └── demo-interactions.ts # Demo: NFT mint, stake, vote
│   ├── AUDIT_REPORT.md          # Relatório de auditoria
│   └── deployed-addresses.json  # Endereços após deploy
├── frontend/
│   ├── app/
│   │   ├── staking/page.tsx     # UI de Staking
│   │   └── governance/page.tsx  # UI de Governança DAO
│   └── abi/
│       ├── EscrowToken.json
│       ├── EscrowNFT.json
│       ├── EscrowStaking.json
│       └── EscrowGovernance.json
└── backend/
    └── ...
```

---

## 🧪 Etapas de Entrega (Checklist)

- [x] **Etapa 1** — Modelagem: arquitetura definida, padrões ERC justificados
- [x] **Etapa 2** — Implementação: ERC-20, ERC-721, Staking, Governança
- [x] **Etapa 3** — Segurança: ReentrancyGuard, Ownable, Solidity ^0.8, auditoria manual
- [x] **Etapa 4** — Oráculo: Chainlink ETH/USD integrado no Staking
- [x] **Etapa 5** — Integração Web3: frontend ethers/wagmi + script de demo
- [ ] **Etapa 6** — Deploy Sepolia: aguardando execução do `deploy-all.ts`
