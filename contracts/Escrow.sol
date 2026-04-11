// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Escrow {
    struct Payment {
        address buyer;
        address seller;
        uint256 amount;
        bool released;
        uint256 createdAt;
    }

    uint256 public paymentCount;
    mapping(uint256 => Payment) public payments;

    event PaymentCreated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
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
        uint256 timestamp
    );

    function pay(address seller, bool isEscrow) external payable {
        require(msg.value > 0, "Valor deve ser maior que zero");
        require(seller != address(0), "Seller invalido");

        if (isEscrow) {
            payments[paymentCount] = Payment({
                buyer: msg.sender,
                seller: seller,
                amount: msg.value,
                released: false,
                createdAt: block.timestamp
            });

            emit PaymentCreated(
                paymentCount,
                msg.sender,
                seller,
                msg.value,
                block.timestamp
            );

            paymentCount++;
        } else {
            // FLUXO E-COMMERCE (DIRETO)
            payable(seller).transfer(msg.value);

            emit InstantPaymentReleased(
                msg.sender,
                seller,
                msg.value,
                block.timestamp
            );
        }
    }

    function release(uint256 id) external {
        Payment storage p = payments[id];
        require(msg.sender == p.buyer, "Apenas o comprador pode liberar");
        require(!p.released, "Ja foi liberado");
        require(p.amount > 0, "Pagamento nao existe");

        p.released = true;
        payable(p.seller).transfer(p.amount);

        emit PaymentReleased(
            id,
            p.seller,
            p.amount,
            block.timestamp
        );
    }
}