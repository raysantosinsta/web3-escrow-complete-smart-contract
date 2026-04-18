// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./EscrowToken.sol";

/**
 * @title EscrowStaking
 * @dev Contrato de staking do protocolo PayWeb3.
 *
 *      Mecânica:
 *      - Usuários fazem stake de tokens ESC
 *      - Recompensa base: 10% ao ano (APY base)
 *      - Recompensa ajustada pelo preço ETH/USD via Chainlink:
 *        APY ajustado = APY_BASE * (precoETH / PRECO_REFERENCIA)
 *        Ex: Se ETH = $4000 (2x o ref de $2000), APY = 20%
 *
 *      Segurança:
 *      - ReentrancyGuard em todas as funções de transferência
 *      - Checks-Effects-Interactions em withdraw/claim
 */
contract EscrowStaking is ReentrancyGuard, Ownable {
    EscrowToken public immutable escrowToken;
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    // Configuração de recompensas
    uint256 public constant APY_BASE = 10;                    // 10% ao ano base
    uint256 public constant PRECO_ETH_REFERENCIA = 2000;      // USD (preço de referência)
    uint256 public constant MAX_APY = 50;                     // Cap: 50% ao ano
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    struct StakeInfo {
        uint256 amount;        // Tokens em stake
        uint256 stakedAt;      // Timestamp do último stake/claim
        uint256 rewardDebt;    // Recompensas acumuladas não sacadas
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 rewardAmount, uint256 ethPrice);
    event PriceFeedUpdated(address indexed newFeed);

    constructor(
        address _escrowToken,
        address _ethUsdPriceFeed,
        address initialOwner
    ) Ownable(initialOwner) {
        escrowToken = EscrowToken(_escrowToken);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
    }

    // ─────────────────────────────────────────────────────────
    //  FUNÇÕES PRINCIPAIS
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Faz stake de tokens ESC.
     *      O usuário deve ter aprovado este contrato antes (ERC20.approve).
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Staking: Valor deve ser maior que zero");

        // Acumula recompensas pendentes antes de alterar o stake
        _accrueRewards(msg.sender);

        stakes[msg.sender].amount += amount;
        totalStaked += amount;

        // Transfers tokens do usuário para o contrato
        bool success = escrowToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Staking: Falha na transferencia");

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Remove tokens do stake. Continua acumulando recompensas até o momento.
     */
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        require(info.amount >= amount, "Staking: Saldo insuficiente em stake");
        require(amount > 0, "Staking: Valor deve ser maior que zero");

        // Acumula recompensas antes de alterar o stake
        _accrueRewards(msg.sender);

        // Checks-Effects-Interactions
        info.amount -= amount;
        totalStaked -= amount;

        bool success = escrowToken.transfer(msg.sender, amount);
        require(success, "Staking: Falha ao devolver tokens");

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev Saca as recompensas acumuladas sem remover o stake principal.
     */
    function claimRewards() external nonReentrant {
        _accrueRewards(msg.sender);

        StakeInfo storage info = stakes[msg.sender];
        uint256 rewards = info.rewardDebt;
        require(rewards > 0, "Staking: Sem recompensas para sacar");

        // Checks-Effects-Interactions
        info.rewardDebt = 0;

        uint256 ethPrice = _getEthPrice();

        // Mint de novos tokens como recompensa
        escrowToken.mint(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards, ethPrice);
    }

    // ─────────────────────────────────────────────────────────
    //  LÓGICA DE RECOMPENSAS
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Calcula e acumula recompensas pendentes para o usuário.
     */
    function _accrueRewards(address user) internal {
        StakeInfo storage info = stakes[user];
        if (info.amount == 0) {
            info.stakedAt = block.timestamp;
            return;
        }

        uint256 pending = _calculatePendingRewards(user);
        info.rewardDebt += pending;
        info.stakedAt = block.timestamp;
    }

    /**
     * @dev Calcula recompensas pendentes sem fazer alterações de estado.
     */
    function _calculatePendingRewards(address user) internal view returns (uint256) {
        StakeInfo storage info = stakes[user];
        if (info.amount == 0 || info.stakedAt == 0) return 0;

        uint256 timeElapsed = block.timestamp - info.stakedAt;
        uint256 ethPrice = _getEthPrice();

        // APY ajustado pelo preço do ETH (cap em MAX_APY)
        uint256 adjustedApy = (APY_BASE * ethPrice) / PRECO_ETH_REFERENCIA;
        if (adjustedApy > MAX_APY) adjustedApy = MAX_APY;

        // Recompensa = stake * APY_ajustado * tempo / ano / 100
        return (info.amount * adjustedApy * timeElapsed) / (SECONDS_PER_YEAR * 100);
    }

    // ─────────────────────────────────────────────────────────
    //  CHAINLINK ORACLE
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Consulta o preço atual do ETH em USD via Chainlink.
     *      Retorna o preço em USD sem decimais (ex: 2456 = $2456).
     */
    function _getEthPrice() internal view returns (uint256) {
        try ethUsdPriceFeed.latestRoundData() returns (
            uint80,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            require(price > 0, "Staking: Preco invalido do oraculo");
            require(block.timestamp - updatedAt <= 3600, "Staking: Oraculo desatualizado");
            // Chainlink ETH/USD tem 8 decimais, converter para USD inteiro
            return uint256(price) / 1e8;
        } catch {
            // Fallback: usa preço de referência caso oráculo falhe
            return PRECO_ETH_REFERENCIA;
        }
    }

    // ─────────────────────────────────────────────────────────
    //  VIEWS PÚBLICAS
    // ─────────────────────────────────────────────────────────

    /**
     * @dev Retorna informações de stake e recompensas pendentes de um usuário.
     */
    function getUserStakeInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 pendingRewards,
        uint256 rewardDebt,
        uint256 currentEthPrice,
        uint256 currentApy
    ) {
        StakeInfo storage info = stakes[user];
        uint256 ethPrice = _getEthPrice();
        uint256 adjustedApy = (APY_BASE * ethPrice) / PRECO_ETH_REFERENCIA;
        if (adjustedApy > MAX_APY) adjustedApy = MAX_APY;

        return (
            info.amount,
            _calculatePendingRewards(user),
            info.rewardDebt,
            ethPrice,
            adjustedApy
        );
    }

    /**
     * @dev Retorna o preço atual do ETH via Chainlink.
     */
    function getEthPrice() external view returns (uint256) {
        return _getEthPrice();
    }
}
