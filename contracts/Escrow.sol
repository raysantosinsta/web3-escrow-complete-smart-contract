// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Escrow {
    address public platformAdmin;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public feeBasisPoints = 100; // 1% default

    struct Payment {
        address buyer;
        address seller;
        uint256 netAmount; // Valor após taxas
        bool released;
        uint256 createdAt;
    }

    uint256 public paymentCount;
    mapping(uint256 => Payment) public payments;

    constructor() {
        platformAdmin = msg.sender;
    }

    event PaymentCreated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );

    event PaymentReleased(
        uint256 indexed id,
        address indexed seller,
        uint256 amount,
        uint256 timestamp
    );

    event InstantPaymentReleased(
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );

    event PaymentDeposited(
        address indexed client,
        address indexed freelancer,
        uint256 amount,
        uint256 paymentId,
        uint256 timestamp
    );


    function updateFee(uint256 _newFee) external {
        require(msg.sender == platformAdmin, "Apenas admin");
        require(_newFee <= 500, "Taxa maxima 5%");
        feeBasisPoints = _newFee;
    }

    function pay(address seller, bool isEscrow) external payable {
        require(msg.value > 0, "Valor deve ser maior que zero");
        require(seller != address(0), "Seller invalido");

        uint256 fee = (msg.value * feeBasisPoints) / BASIS_POINTS;
        uint256 netAmount = msg.value - fee;

        if (isEscrow) {
            payments[paymentCount] = Payment({
                buyer: msg.sender,
                seller: seller,
                netAmount: netAmount,
                released: false,
                createdAt: block.timestamp
            });

            // Admin recebe a taxa na hora do financiamento
            if (fee > 0) payable(platformAdmin).transfer(fee);

            emit PaymentCreated(
                paymentCount,
                msg.sender,
                seller,
                netAmount,
                fee,
                block.timestamp
            );

            emit PaymentDeposited(
                msg.sender,
                seller,
                netAmount,
                paymentCount,
                block.timestamp
            );


            paymentCount++;
        } else {
            // FLUXO E-COMMERCE (DIRETO)
            payable(seller).transfer(netAmount);
            if (fee > 0) payable(platformAdmin).transfer(fee);

            emit InstantPaymentReleased(
                msg.sender,
                seller,
                netAmount,
                fee,
                block.timestamp
            );
        }
    }

    function release(uint256 id) external {
        Payment storage p = payments[id];
        require(msg.sender == p.buyer, "Apenas o comprador pode liberar");
        require(!p.released, "Ja foi liberado");
        require(p.netAmount > 0, "Pagamento nao existe");

        p.released = true;
        payable(p.seller).transfer(p.netAmount);

        emit PaymentReleased(
            id,
            p.seller,
            p.netAmount,
            block.timestamp
        );
    }
}