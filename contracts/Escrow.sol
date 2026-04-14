// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Escrow Secure
 * @dev Contrato de custódia seguro com máquina de estados, proteção contra reentrância e mediação.
 */
contract Escrow is ReentrancyGuard {
    address public platformAdmin;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public feeBasisPoints = 100; // 1% default

    enum Status { 
        NEGOTIATING, // Criado no DB, aguardando fundos no contrato
        FUNDED,      // Dinheiro bloqueado no contrato
        REVIEWING,   // Freelancer entregou, aguardando aprovação
        COMPLETED,   // Pagamento liberado ao freelancer
        DISPUTED,    // Em disputa por uma das partes
        REFUNDED     // Estornado ao cliente
    }

    struct Payment {
        address buyer;
        address seller;
        uint256 netAmount;
        uint256 feeAmount;
        Status status;
        uint256 createdAt;
        uint256 updatedAt;
    }

    uint256 public paymentCount;
    mapping(uint256 => Payment) public payments;

    // --- Eventos ---
    event PaymentCreated(uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount, uint256 fee);
    event StatusChanged(uint256 indexed id, Status indexed oldStatus, Status indexed newStatus);
    event FundsReleased(uint256 indexed id, address indexed seller, uint256 amount);
    event FundsRefunded(uint256 indexed id, address indexed buyer, uint256 amount);
    event DisputeOpened(uint256 indexed id, address indexed opener);

    // --- Modificadores ---
    modifier onlyAdmin() {
        require(msg.sender == platformAdmin, "Escrow: Apenas administrador");
        _;
    }

    modifier onlyBuyer(uint256 id) {
        require(msg.sender == payments[id].buyer, "Escrow: Apenas comprador");
        _;
    }

    modifier onlySeller(uint256 id) {
        require(msg.sender == payments[id].seller, "Escrow: Apenas vendedor");
        _;
    }

    modifier inStatus(uint256 id, Status requiredStatus) {
        require(payments[id].status == requiredStatus, "Escrow: Operacao invalida para o status atual");
        _;
    }

    constructor() {
        platformAdmin = msg.sender;
    }

    /**
     * @dev Transfere a administração (arbitragem)
     */
    function transferAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Novo admin nao pode ser zero");
        platformAdmin = _newAdmin;
    }

    /**
     * @dev Atualiza taxa do protocolo
     */
    function updateFee(uint256 _newFee) external onlyAdmin {
        require(_newFee <= 500, "Escrow: Taxa maxima 5%");
        feeBasisPoints = _newFee;
    }

    /**
     * @dev Cria e financia um novo Escrow
     */
    function pay(address seller, address buyer, bool isEscrow) external payable nonReentrant {
        require(msg.value > 0, "Escrow: Valor invalido");
        require(seller != address(0) && buyer != address(0), "Escrow: Enderecos invalidos");

        uint256 fee = (msg.value * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = msg.value - fee;

        if (isEscrow) {
            uint256 id = paymentCount++;
            payments[id] = Payment({
                buyer: buyer,
                seller: seller,
                netAmount: netAmount,
                feeAmount: fee,
                status: Status.FUNDED,
                createdAt: block.timestamp,
                updatedAt: block.timestamp
            });

            // Admin recebe a taxa na hora do financiamento para evitar bloqueio de taxas em caso de disputa
            if (fee > 0) {
                (bool success, ) = payable(platformAdmin).call{value: fee}("");
                require(success, "Escrow: Falha ao transferir taxa");
            }

            emit PaymentCreated(id, buyer, seller, netAmount, fee);
            emit StatusChanged(id, Status.NEGOTIATING, Status.FUNDED);
        } else {
            // Pagamento Direto (sem custódia)
            (bool s1, ) = payable(seller).call{value: netAmount}("");
            require(s1, "Escrow: Falha ao pagar vendedor");
            
            if (fee > 0) {
                (bool s2, ) = payable(platformAdmin).call{value: fee}("");
                require(s2, "Escrow: Falha ao pagar taxa");
            }
        }
    }

    /**
     * @dev Freelancer marca como entregue
     */
    function markAsDelivered(uint256 id) external onlySeller(id) inStatus(id, Status.FUNDED) {
        payments[id].status = Status.REVIEWING;
        payments[id].updatedAt = block.timestamp;
        emit StatusChanged(id, Status.FUNDED, Status.REVIEWING);
    }

    /**
     * @dev Comprador libera os fundos
     */
    function release(uint256 id) external onlyBuyer(id) nonReentrant {
        Payment storage p = payments[id];
        require(p.status == Status.FUNDED || p.status == Status.REVIEWING, "Escrow: Status invalido");

        uint256 amount = p.netAmount;
        address seller = p.seller;

        p.status = Status.COMPLETED;
        p.updatedAt = block.timestamp;
        p.netAmount = 0; // Proteção contra reentrância manual extra

        (bool success, ) = payable(seller).call{value: amount}("");
        require(success, "Escrow: Falha no pagamento");

        emit FundsReleased(id, seller, amount);
        emit StatusChanged(id, Status.REVIEWING, Status.COMPLETED);
    }

    /**
     * @dev Inicia uma disputa (Pode ser chamado por qualquer uma das partes)
     */
    function openDispute(uint256 id) external nonReentrant {
        Payment storage p = payments[id];
        require(msg.sender == p.buyer || msg.sender == p.seller, "Escrow: Nao autorizado");
        require(p.status == Status.FUNDED || p.status == Status.REVIEWING, "Escrow: Status invalido");

        p.status = Status.DISPUTED;
        p.updatedAt = block.timestamp;

        emit DisputeOpened(id, msg.sender);
        emit StatusChanged(id, Status.FUNDED, Status.DISPUTED);
    }

    /**
     * @dev Resolve disputa (Apenas Admin/Arbitro)
     */
    function resolveDispute(uint256 id, uint256 releaseToSellerAmount, uint256 refundToBuyerAmount) external onlyAdmin nonReentrant {
        Payment storage p = payments[id];
        require(p.status == Status.DISPUTED, "Escrow: Nao esta em disputa");
        require(releaseToSellerAmount + refundToBuyerAmount == p.netAmount, "Escrow: Soma deve ser igual ao total");

        p.status = Status.COMPLETED;
        p.updatedAt = block.timestamp;
        p.netAmount = 0;

        if (releaseToSellerAmount > 0) {
            (bool s1, ) = payable(p.seller).call{value: releaseToSellerAmount}("");
            require(s1, "Escrow: Falha ao pagar seller");
        }

        if (refundToBuyerAmount > 0) {
            (bool s2, ) = payable(p.buyer).call{value: refundToBuyerAmount}("");
            require(s2, "Escrow: Falha ao reembolsar buyer");
        }

        emit StatusChanged(id, Status.DISPUTED, Status.COMPLETED);
    }

    /**
     * @dev Reembolso total (Pode ser concedido pelo Seller ou Admin)
     */
    function refund(uint256 id) external nonReentrant {
        Payment storage p = payments[id];
        require(msg.sender == p.seller || msg.sender == platformAdmin, "Escrow: Nao autorizado");
        require(p.status == Status.FUNDED || p.status == Status.REVIEWING || p.status == Status.DISPUTED, "Escrow: Status invalido");

        uint256 amount = p.netAmount;
        address buyer = p.buyer;

        p.status = Status.REFUNDED;
        p.updatedAt = block.timestamp;
        p.netAmount = 0;

        (bool success, ) = payable(buyer).call{value: amount}("");
        require(success, "Escrow: Falha ao reembolsar");

        emit FundsRefunded(id, buyer, amount);
        emit StatusChanged(id, p.status, Status.REFUNDED);
    }
}