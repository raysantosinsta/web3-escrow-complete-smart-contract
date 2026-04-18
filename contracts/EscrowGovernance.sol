// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./EscrowToken.sol";

/**
 * @title EscrowGovernance — DAO Simplificada
 * @dev Contrato de governança do protocolo PayWeb3.
 *
 *      Mecânica:
 *      - Qualquer holder com >= 100 ESC pode criar uma proposta
 *      - Período de votação: 3 dias
 *      - Votação ponderada pelo saldo de tokens (1 ESC = 1 voto)
 *      - Quórum mínimo: 1000 ESC (votos a favor)
 *      - Propostas aprovadas podem ser executadas via calldata on-chain
 *
 *      Segurança:
 *      - Controle de acesso via token
 *      - Um voto por endereço por proposta
 *      - Período de execução: apenas após votação encerrada e aprovada
 */
contract EscrowGovernance is Ownable {
    EscrowToken public immutable governanceToken;

    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MIN_TOKENS_TO_PROPOSE = 100 * 10 ** 18;  // 100 ESC
    uint256 public constant QUORUM = 1000 * 10 ** 18;                 // 1000 ESC em votos

    uint256 private _proposalCount;

    enum ProposalStatus { ACTIVE, APPROVED, REJECTED, EXECUTED }

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        uint256 createdAt;
        uint256 votingDeadline;
        uint256 votesFor;
        uint256 votesAgainst;
        ProposalStatus status;
        // Para execução on-chain opcional
        address targetContract;
        bytes callData;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => uint256)) public votesOf;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 votingDeadline
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _governanceToken, address initialOwner) Ownable(initialOwner) {
        governanceToken = EscrowToken(_governanceToken);
    }

    // ─────────────────────────────────────────────────────────
    //  CRIAR PROPOSTA
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Cria uma nova proposta de governança.
     * @param title Título da proposta
     * @param description Descrição detalhada
     * @param targetContract Endereço do contrato alvo (address(0) se sem execução)
     * @param callData Dados da chamada a executar (bytes("") se sem execução)
     */
    function propose(
        string memory title,
        string memory description,
        address targetContract,
        bytes memory callData
    ) external returns (uint256) {
        require(
            governanceToken.balanceOf(msg.sender) >= MIN_TOKENS_TO_PROPOSE,
            "Governance: Saldo insuficiente para propor (min 100 ESC)"
        );
        require(bytes(title).length > 0, "Governance: Titulo nao pode ser vazio");
        require(bytes(description).length > 0, "Governance: Descricao nao pode ser vazia");

        uint256 proposalId = _proposalCount++;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            createdAt: block.timestamp,
            votingDeadline: block.timestamp + VOTING_PERIOD,
            votesFor: 0,
            votesAgainst: 0,
            status: ProposalStatus.ACTIVE,
            targetContract: targetContract,
            callData: callData,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, title, block.timestamp + VOTING_PERIOD);
        return proposalId;
    }

    // ─────────────────────────────────────────────────────────
    //  VOTAR
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Vota em uma proposta ativa. Peso do voto = saldo de ESC no momento.
     * @param proposalId ID da proposta
     * @param support true = a favor, false = contra
     */
    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];

        require(p.createdAt > 0, "Governance: Proposta nao existe");
        require(p.status == ProposalStatus.ACTIVE, "Governance: Proposta nao esta ativa");
        require(block.timestamp <= p.votingDeadline, "Governance: Periodo de votacao encerrado");
        require(!hasVoted[proposalId][msg.sender], "Governance: Ja votou nesta proposta");

        uint256 weight = governanceToken.balanceOf(msg.sender);
        require(weight > 0, "Governance: Sem tokens para votar");

        hasVoted[proposalId][msg.sender] = true;
        votesOf[proposalId][msg.sender] = weight;

        if (support) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    // ─────────────────────────────────────────────────────────
    //  FINALIZAR PROPOSTA
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Finaliza uma proposta após o período de votação.
     *      Qualquer pessoa pode chamar esta função.
     */
    function finalizeProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];

        require(p.createdAt > 0, "Governance: Proposta nao existe");
        require(p.status == ProposalStatus.ACTIVE, "Governance: Proposta ja finalizada");
        require(block.timestamp > p.votingDeadline, "Governance: Votacao ainda ativa");

        if (p.votesFor >= QUORUM && p.votesFor > p.votesAgainst) {
            p.status = ProposalStatus.APPROVED;
        } else {
            p.status = ProposalStatus.REJECTED;
        }

        emit ProposalFinalized(proposalId, p.status);
    }

    // ─────────────────────────────────────────────────────────
    //  EXECUTAR PROPOSTA
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Executa uma proposta aprovada com calldata on-chain.
     *      Apenas admin pode executar para evitar ataques de replay.
     */
    function executeProposal(uint256 proposalId) external onlyOwner {
        Proposal storage p = proposals[proposalId];

        require(p.status == ProposalStatus.APPROVED, "Governance: Proposta nao aprovada");
        require(!p.executed, "Governance: Proposta ja executada");
        require(p.targetContract != address(0), "Governance: Sem contrato alvo");

        p.executed = true;
        p.status = ProposalStatus.EXECUTED;

        (bool success, ) = p.targetContract.call(p.callData);
        require(success, "Governance: Execucao falhou");

        emit ProposalExecuted(proposalId);
    }

    // ─────────────────────────────────────────────────────────
    //  VIEWS PÚBLICAS
    // ─────────────────────────────────────────────────────────

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        require(proposals[proposalId].createdAt > 0, "Governance: Proposta nao existe");
        return proposals[proposalId];
    }

    function proposalCount() external view returns (uint256) {
        return _proposalCount;
    }

    function getVotingPower(address voter) external view returns (uint256) {
        return governanceToken.balanceOf(voter);
    }

    function isActive(uint256 proposalId) external view returns (bool) {
        Proposal storage p = proposals[proposalId];
        return p.status == ProposalStatus.ACTIVE && block.timestamp <= p.votingDeadline;
    }
}
