// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title EscrowBadge (ERC-721)
 * @dev NFT de certificação para freelancers do protocolo PayWeb3.
 *      Emitido pelo admin quando freelancer atinge marcos de reputação.
 *      Metadata gerada on-chain via SVG em base64 — sem necessidade de IPFS.
 */
contract EscrowNFT is ERC721, ERC721URIStorage, Ownable {
    using Strings for uint256;

    uint256 private _nextTokenId;

    // Níveis de badge
    enum BadgeLevel { BRONZE, SILVER, GOLD, PLATINUM }

    struct BadgeMetadata {
        BadgeLevel level;
        string freelancerName;
        uint256 completedEscrows;
        uint256 mintedAt;
    }

    mapping(uint256 => BadgeMetadata) public badges;
    mapping(address => uint256) public freelancerBadge; // endereço => tokenId (0 = sem badge)
    mapping(address => bool) public hasBadge;

    event BadgeMinted(address indexed freelancer, uint256 indexed tokenId, BadgeLevel level);
    event BadgeUpgraded(uint256 indexed tokenId, BadgeLevel oldLevel, BadgeLevel newLevel);

    constructor(address initialOwner) ERC721("EscrowBadge", "ESCBDG") Ownable(initialOwner) {}

    /**
     * @dev Mint de badge para freelancer. Apenas owner/admin.
     */
    function mintBadge(
        address freelancer,
        string memory freelancerName,
        uint256 completedEscrows
    ) external onlyOwner returns (uint256) {
        require(!hasBadge[freelancer], "EscrowNFT: Freelancer ja possui badge");

        uint256 tokenId = _nextTokenId++;
        BadgeLevel level = _calculateLevel(completedEscrows);

        badges[tokenId] = BadgeMetadata({
            level: level,
            freelancerName: freelancerName,
            completedEscrows: completedEscrows,
            mintedAt: block.timestamp
        });

        hasBadge[freelancer] = true;
        freelancerBadge[freelancer] = tokenId;

        _safeMint(freelancer, tokenId);
        _setTokenURI(tokenId, _generateTokenURI(tokenId));

        emit BadgeMinted(freelancer, tokenId, level);
        return tokenId;
    }

    /**
     * @dev Atualiza o nível do badge conforme novos escrows completados.
     */
    function upgradeBadge(uint256 tokenId, uint256 newCompletedEscrows) external onlyOwner {
        BadgeMetadata storage badge = badges[tokenId];
        BadgeLevel oldLevel = badge.level;

        badge.completedEscrows = newCompletedEscrows;
        badge.level = _calculateLevel(newCompletedEscrows);

        _setTokenURI(tokenId, _generateTokenURI(tokenId));

        if (badge.level != oldLevel) {
            emit BadgeUpgraded(tokenId, oldLevel, badge.level);
        }
    }

    /**
     * @dev Calcula nível do badge baseado em escrows completados.
     */
    function _calculateLevel(uint256 completed) internal pure returns (BadgeLevel) {
        if (completed >= 100) return BadgeLevel.PLATINUM;
        if (completed >= 50) return BadgeLevel.GOLD;
        if (completed >= 10) return BadgeLevel.SILVER;
        return BadgeLevel.BRONZE;
    }

    /**
     * @dev Retorna a cor do badge conforme o nível.
     */
    function _levelColor(BadgeLevel level) internal pure returns (string memory) {
        if (level == BadgeLevel.PLATINUM) return "#E5E4E2";
        if (level == BadgeLevel.GOLD) return "#FFD700";
        if (level == BadgeLevel.SILVER) return "#C0C0C0";
        return "#CD7F32"; // BRONZE
    }

    function _levelName(BadgeLevel level) internal pure returns (string memory) {
        if (level == BadgeLevel.PLATINUM) return "PLATINUM";
        if (level == BadgeLevel.GOLD) return "GOLD";
        if (level == BadgeLevel.SILVER) return "SILVER";
        return "BRONZE";
    }

    /**
     * @dev Gera o tokenURI com SVG e JSON codificados em base64 (on-chain).
     */
    function _generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        BadgeMetadata memory badge = badges[tokenId];
        string memory badgeColor = _levelColor(badge.level);
        string memory levelName = _levelName(badge.level);

        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350" viewBox="0 0 350 350">',
            '<defs><linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" style="stop-color:#0a0a1a"/><stop offset="100%" style="stop-color:#1a1a3a"/>',
            '</linearGradient></defs>',
            '<rect width="350" height="350" rx="20" fill="url(#bg)"/>',
            '<circle cx="175" cy="120" r="60" fill="none" stroke="', badgeColor, '" stroke-width="4" opacity="0.8"/>',
            '<text x="175" y="130" text-anchor="middle" font-family="Arial" font-size="48" fill="', badgeColor, '">&#9632;</text>',
            '<text x="175" y="195" text-anchor="middle" font-family="Arial" font-weight="bold" font-size="14" fill="', badgeColor, '">', levelName, ' FREELANCER</text>',
            '<text x="175" y="220" text-anchor="middle" font-family="Arial" font-size="12" fill="#aaaacc">', badge.freelancerName, '</text>',
            '<text x="175" y="250" text-anchor="middle" font-family="Arial" font-size="11" fill="#8888aa">',
            badge.completedEscrows.toString(), ' escrows concluidos</text>',
            '<text x="175" y="310" text-anchor="middle" font-family="Arial" font-size="10" fill="#555577">PayWeb3 Protocol - Verified</text>',
            '</svg>'
        ));

        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name":"EscrowBadge #', tokenId.toString(), ' - ', levelName, '",',
            '"description":"Badge de certificacao de freelancer no protocolo PayWeb3.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            '"attributes":[',
            '{"trait_type":"Level","value":"', levelName, '"},',
            '{"trait_type":"Freelancer","value":"', badge.freelancerName, '"},',
            '{"trait_type":"Completed Escrows","value":', badge.completedEscrows.toString(), '},',
            '{"trait_type":"Minted At","value":', badge.mintedAt.toString(), '}',
            ']}'
        ))));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // --- Overrides necessários pelo ERC721URIStorage ---

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
