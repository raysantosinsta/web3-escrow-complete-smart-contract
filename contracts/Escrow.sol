// SPDX-License-Identifier: MIT
// ==========================================================
// LICENÇA:
// MIT → permissiva, permite uso, modificação e distribuição.
// É padrão no ecossistema Ethereum, facilita auditoria e adoção.
// ==========================================================

pragma solidity ^0.8.20;
// ==========================================================
// COMPILADOR:
// ^0.8.x → inclui proteção automática contra overflow/underflow.
// Antes (<=0.7) era necessário usar SafeMath.
// ==========================================================

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// ==========================================================
// SEGURANÇA:
// ReentrancyGuard → protege contra ataques de reentrância.
//
// Reentrância:
// Um contrato malicioso chama de volta o contrato antes da execução terminar,
// podendo explorar estado inconsistente.
//
// Implementação:
// Usa um "mutex" interno (_status) para bloquear reentrada.
// ==========================================================

/**
 * @title Escrow Secure
 * @dev
 * Contrato de custódia (escrow) com:
 * - Máquina de estados finitos (FSM)
 * - Controle de acesso
 * - Proteção contra reentrância
 * - Sistema de disputa e arbitragem
 * - Cobrança de taxa da plataforma
 *
 * CASO DE USO:
 * - Freelancers
 * - Marketplaces
 * - Pagamentos condicionais
 */
contract Escrow is ReentrancyGuard {

    // ==========================================================
    // VARIÁVEIS DE ESTADO
    // ==========================================================

    // Endereço do administrador (árbitro)
    // Responsável por:
    // - resolver disputas
    // - atualizar taxas
    // - governança do contrato
    address public platformAdmin;

    // Base para cálculo percentual (10000 = 100%)
    // Permite representar porcentagens sem float
    uint256 public constant BASIS_POINTS = 10000;

    // Taxa da plataforma em basis points
    // 100 = 1%, 250 = 2.5%
    uint256 public feeBasisPoints = 100;

    // ==========================================================
    // ENUM → MÁQUINA DE ESTADOS (FSM)
    // ==========================================================

    /**
     * FSM (Finite State Machine):
     * Garante que o contrato siga um fluxo lógico previsível.
     *
     * Isso evita:
     * - estados inválidos
     * - execução fora de ordem
     */
    enum Status { 
        NEGOTIATING, // Estado off-chain (DB)
        FUNDED,      // Fundos depositados no contrato
        REVIEWING,   // Seller marcou como entregue
        COMPLETED,   // Pagamento finalizado
        DISPUTED,    // Em disputa
        REFUNDED     // Reembolsado
    }

    // ==========================================================
    // STRUCT → MODELO DE DADOS
    // ==========================================================

    /**
     * Representa uma instância de pagamento escrow.
     * Cada Payment é independente.
     */
    struct Payment {
        address buyer;        // Cliente (quem paga)
        address seller;       // Freelancer (quem recebe)

        uint256 netAmount;    // Valor líquido (sem taxa)
        uint256 feeAmount;    // Taxa da plataforma

        Status status;        // Estado atual da FSM

        uint256 createdAt;    // Timestamp de criação
        uint256 updatedAt;    // Timestamp de última atualização
    }

    // Contador incremental → gera IDs únicos
    uint256 public paymentCount;

    // Armazena pagamentos por ID
    // Lookup O(1)
    mapping(uint256 => Payment) public payments;

    // ==========================================================
    // EVENTOS → LOGS ON-CHAIN
    // ==========================================================

    /**
     * Eventos não armazenam estado, mas são:
     * - mais baratos que storage
     * - usados por frontends/indexadores (The Graph)
     * - essenciais para auditoria
     */

    event PaymentCreated(uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount, uint256 fee);
    event StatusChanged(uint256 indexed id, Status indexed oldStatus, Status indexed newStatus);
    event FundsReleased(uint256 indexed id, address indexed seller, uint256 amount);
    event FundsRefunded(uint256 indexed id, address indexed buyer, uint256 amount);
    event DisputeOpened(uint256 indexed id, address indexed opener);

    // ==========================================================
    // MODIFIERS → CONTROLE DE ACESSO + VALIDAÇÃO
    // ==========================================================

    modifier onlyAdmin() {
        // Garante que apenas o admin execute
        require(msg.sender == platformAdmin, "Escrow: Apenas administrador");
        _;
    }

    modifier onlyBuyer(uint256 id) {
        // Garante que apenas o comprador daquele pagamento execute
        require(msg.sender == payments[id].buyer, "Escrow: Apenas comprador");
        _;
    }

    modifier onlySeller(uint256 id) {
        // Garante que apenas o vendedor execute
        require(msg.sender == payments[id].seller, "Escrow: Apenas vendedor");
        _;
    }

    modifier inStatus(uint256 id, Status requiredStatus) {
        // Garante consistência da FSM
        require(payments[id].status == requiredStatus, "Escrow: Operacao invalida");
        _;
    }

    // ==========================================================
    // CONSTRUCTOR
    // ==========================================================

    constructor() {
        // Quem deploya vira admin
        platformAdmin = msg.sender;
    }

    // ==========================================================
    // ADMIN FUNCTIONS
    // ==========================================================

    function transferAdmin(address _newAdmin) external onlyAdmin {
        // Evita endereço inválido
        require(_newAdmin != address(0), "Endereco invalido");
        platformAdmin = _newAdmin;
    }

    function updateFee(uint256 _newFee) external onlyAdmin {
        // Limite de segurança (5%)
        require(_newFee <= 500, "Max 5%");
        feeBasisPoints = _newFee;
    }

    // ==========================================================
    // FUNÇÃO PRINCIPAL → PAY
    // ==========================================================

    /**
     * @dev Cria pagamento (escrow ou direto)
     *
     * Segurança:
     * - nonReentrant → evita reentrância
     */
    function pay(address seller, address buyer, bool isEscrow) 
        external 
        payable 
        nonReentrant 
    {
        // ======================================================
        // VALIDAÇÕES (CHECKS)
        // ======================================================

        require(msg.value > 0, "Valor invalido");
        require(seller != address(0) && buyer != address(0), "Endereco invalido");

        // ======================================================
        // CÁLCULO ECONÔMICO
        // ======================================================

        uint256 fee = (msg.value * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = msg.value - fee;

        // ======================================================
        // MODO ESCROW
        // ======================================================

        if (isEscrow) {
            uint256 id = paymentCount++;

            // EFFECTS → atualiza estado antes de interação externa
            payments[id] = Payment({
                buyer: buyer,
                seller: seller,
                netAmount: netAmount,
                feeAmount: fee,
                status: Status.FUNDED,
                createdAt: block.timestamp,
                updatedAt: block.timestamp
            });

            // INTERACTION → envio da taxa
            if (fee > 0) {
                // call:
                // - envia ETH
                // - permite execução de código no destinatário
                // - retorna sucesso/falha
                (bool success, ) = payable(platformAdmin).call{value: fee}("");

                // SEM require → risco de perda silenciosa
                require(success, "Falha taxa");
            }

            emit PaymentCreated(id, buyer, seller, netAmount, fee);
            emit StatusChanged(id, Status.NEGOTIATING, Status.FUNDED);

        } else {
            // ==================================================
            // PAGAMENTO DIRETO
            // ==================================================

            (bool s1, ) = payable(seller).call{value: netAmount}("");
            require(s1, "Falha seller");

            if (fee > 0) {
                (bool s2, ) = payable(platformAdmin).call{value: fee}("");
                require(s2, "Falha taxa");
            }
        }
    }

    // ==========================================================
    // SELLER → ENTREGA
    // ==========================================================

    function markAsDelivered(uint256 id)
        external
        onlySeller(id)
        inStatus(id, Status.FUNDED)
    {
        payments[id].status = Status.REVIEWING;
        payments[id].updatedAt = block.timestamp;

        emit StatusChanged(id, Status.FUNDED, Status.REVIEWING);
    }

    // ==========================================================
    // BUYER → LIBERA PAGAMENTO
    // ==========================================================

    function release(uint256 id)
        external
        onlyBuyer(id)
        nonReentrant
    {
        Payment storage p = payments[id];

        require(
            p.status == Status.FUNDED || p.status == Status.REVIEWING,
            "Status invalido"
        );

        uint256 amount = p.netAmount;
        address seller = p.seller;

        // ======================================================
        // EFFECTS (ANTES DA INTERAÇÃO)
        // ======================================================

        p.status = Status.COMPLETED;
        p.updatedAt = block.timestamp;

        // CRÍTICO:
        // Zera antes da transferência para evitar reentrância
        p.netAmount = 0;

        // ======================================================
        // INTERACTION (RISCO)
        // ======================================================

        (bool success, ) = payable(seller).call{value: amount}("");

        // Sempre validar retorno
        require(success, "Falha pagamento");

        emit FundsReleased(id, seller, amount);
        emit StatusChanged(id, Status.REVIEWING, Status.COMPLETED);
    }

    // ==========================================================
    // DISPUTA
    // ==========================================================

    function openDispute(uint256 id) external nonReentrant {
        Payment storage p = payments[id];

        require(msg.sender == p.buyer || msg.sender == p.seller, "Nao autorizado");

        require(
            p.status == Status.FUNDED || p.status == Status.REVIEWING,
            "Status invalido"
        );

        p.status = Status.DISPUTED;
        p.updatedAt = block.timestamp;

        emit DisputeOpened(id, msg.sender);
        emit StatusChanged(id, Status.FUNDED, Status.DISPUTED);
    }

    // ==========================================================
    // RESOLUÇÃO DE DISPUTA
    // ==========================================================

    function resolveDispute(
        uint256 id,
        uint256 releaseToSellerAmount,
        uint256 refundToBuyerAmount
    )
        external
        onlyAdmin
        nonReentrant
    {
        Payment storage p = payments[id];

        require(p.status == Status.DISPUTED, "Nao esta em disputa");

        // ======================================================
        // INVARIANTE FINANCEIRA
        // ======================================================
        // Garante conservação de valor (fundamental)
        require(
            releaseToSellerAmount + refundToBuyerAmount == p.netAmount,
            "Soma invalida"
        );

        p.status = Status.COMPLETED;
        p.updatedAt = block.timestamp;
        p.netAmount = 0;

        // Transferência ao seller
        if (releaseToSellerAmount > 0) {
            (bool s1, ) = payable(p.seller).call{value: releaseToSellerAmount}("");
            require(s1, "Falha seller");
        }

        // Transferência ao buyer
        if (refundToBuyerAmount > 0) {
            (bool s2, ) = payable(p.buyer).call{value: refundToBuyerAmount}("");
            require(s2, "Falha buyer");
        }

        emit StatusChanged(id, Status.DISPUTED, Status.COMPLETED);
    }

    // ==========================================================
    // REEMBOLSO TOTAL
    // ==========================================================

    function refund(uint256 id) external nonReentrant {
        Payment storage p = payments[id];

        require(
            msg.sender == p.seller || msg.sender == platformAdmin,
            "Nao autorizado"
        );

        require(
            p.status == Status.FUNDED ||
            p.status == Status.REVIEWING ||
            p.status == Status.DISPUTED,
            "Status invalido"
        );

        uint256 amount = p.netAmount;
        address buyer = p.buyer;

        p.status = Status.REFUNDED;
        p.updatedAt = block.timestamp;
        p.netAmount = 0;

        // ======================================================
        // LINHA CRÍTICA EXPLICADA:
        // ======================================================
        // - payable(buyer): converte para endereço que pode receber ETH
        // - call{value: amount}: envia ETH
        // - "" → nenhum dado (apenas transferência)
        //
        // RISCOS:
        // - buyer pode ser um contrato malicioso
        // - pode executar fallback()
        //
        // PROTEÇÕES:
        // - nonReentrant
        // - estado já atualizado
        //
        (bool success, ) = payable(buyer).call{value: amount}("");

        require(success, "Falha reembolso");

        emit FundsRefunded(id, buyer, amount);

        // OBS: poderia salvar oldStatus antes para log mais preciso
        emit StatusChanged(id, p.status, Status.REFUNDED);
    }
}