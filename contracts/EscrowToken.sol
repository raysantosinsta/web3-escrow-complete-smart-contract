// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EscrowToken (ESC)
 * @dev Token ERC-20 do protocolo PayWeb3.
 *      Usado para recompensas de staking e votação na DAO.
 */
contract EscrowToken is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 18; // 100 milhões de ESC
    uint256 public totalMinted;
    mapping(address => bool) public faucetUsed;

    event TokensMinted(address indexed to, uint256 amount);
    event FaucetUsed(address indexed to, uint256 amount);

    constructor(address initialOwner) ERC20("EscrowToken", "ESC") Ownable(initialOwner) {
        // Mint inicial de 1 milhão para o deployer (treasury)
        uint256 initialSupply = 1_000_000 * 10 ** 18;
        totalMinted = initialSupply;
        _mint(initialOwner, initialSupply);
    }

    /**
     * @dev Mint de novos tokens. Apenas o owner (protocolo/staking) pode chamar.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalMinted + amount <= MAX_SUPPLY, "ESC: Supply maximo atingido");
        totalMinted += amount;
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @dev Faucet para resgate de tokens de teste. 
     *      Cada endereço pode resgatar 1000 ESC uma única vez.
     */
    function requestTestTokens() external {
        require(!faucetUsed[msg.sender], "ESC: Faucet ja utilizado por este endereco");
        uint256 amount = 1000 * 10 ** 18;
        require(totalMinted + amount <= MAX_SUPPLY, "ESC: Supply maximo atingido");
        
        faucetUsed[msg.sender] = true;
        totalMinted += amount;
        _mint(msg.sender, amount);
        
        emit FaucetUsed(msg.sender, amount);
    }
}
