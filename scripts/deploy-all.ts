import { createWalletClient, createPublicClient, http, parseEther, getContract } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { hardhat, sepolia } from "viem/chains";
import { writeFileSync, readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import hre from "hardhat";

async function main() {
    // No Hardhat v3, pegamos o nome da rede pelos argumentos ou pelo provider
    const networkArgIndex = process.argv.indexOf("--network");
    const networkName = networkArgIndex !== -1 ? process.argv[networkArgIndex + 1] : "localhost";
    console.log(`\n🚀 Iniciando Deploy Blindado na rede: ${networkName}`);

    const PRIVATE_KEY = (process.env.PRIVATE_KEY || "0xc9db5c9ee35683e48d4ed3f4e2158120271398e09545f891147a259e1804702d") as `0x${string}`;
    const chain = networkName === "sepolia" ? sepolia : hardhat;
    const transport = http(networkName === "sepolia" ? process.env.SEPOLIA_RPC_URL : "http://127.0.0.1:8545");

    // Artifacts (ABIs e Bytecodes)
    const getArtifact = (name: string) => {
        const path = join(process.cwd(), "artifacts", "contracts", `${name}.sol`, `${name}.json`);
        return JSON.parse(readFileSync(path, "utf8"));
    };

    const account = privateKeyToAccount(PRIVATE_KEY);
    const walletClient = createWalletClient({ account, chain, transport });
    const publicClient = createPublicClient({ chain, transport });

    console.log(`📍 Deployer: ${account.address}`);

    let priceFeed = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // Sepolia default

    if (networkName === "localhost" || networkName === "hardhat") {
        console.log("\n[0/5] Deployando Oracle Fictício (Local)...");
        // Usamos um bytecode simples que retorna $2500
        const mockArtifact = {
            abi: [{ "inputs": [], "name": "latestRoundData", "outputs": [{ "internalType": "uint80", "name": "roundId", "type": "uint80" }, { "internalType": "int256", "name": "answer", "type": "int256" }, { "internalType": "uint256", "name": "startedAt", "type": "uint256" }, { "internalType": "uint256", "name": "updatedAt", "type": "uint256" }, { "internalType": "uint80", "name": "answeredInRound", "type": "uint80" }], "stateMutability": "view", "type": "function" }],
            bytecode: "0x608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b506004361061002b5760003560e01c8063feaf968c14610030575b600080fd5b61003861004e565b6040516100459594939291906100a3565b60405180910390f35b600080806724576395b0000000809350505091565b6000819050919050565b6000819050919050565b61009d8161008a565b82525050565b600060a0820190506100b86000830188610094565b6100c56020830187610080565b6100d26040830186610080565b6100df6060830185610080565b6100ec6080830184610094565b5095949392919056fea264697066735822122049d53f0980f76901f46d1bf1e2e1d67f7813a3048e5898d9cc9b6742337f71f164736f6c634300081c0033"
        };
        const hashMock = await walletClient.deployContract({
            abi: mockArtifact.abi,
            bytecode: mockArtifact.bytecode as `0x${string}`,
        });
        const receiptMock = await publicClient.waitForTransactionReceipt({ hash: hashMock });
        priceFeed = receiptMock.contractAddress!;
        console.log(`  ✅ Oracle Mock: ${priceFeed} (Preço: $2500)`);
    }

    // 1. EscrowToken
    console.log("\n[1/5] Deployando EscrowToken...");
    const tokenArtifact = getArtifact("EscrowToken");
    const hashToken = await walletClient.deployContract({
        abi: tokenArtifact.abi,
        bytecode: tokenArtifact.bytecode,
        args: [account.address],
    });
    const receiptToken = await publicClient.waitForTransactionReceipt({ hash: hashToken });
    const tokenAddr = receiptToken.contractAddress!;
    console.log(`  ✅ EscrowToken: ${tokenAddr}`);

    // 2. EscrowNFT
    console.log("[2/5] Deployando EscrowNFT...");
    const nftArtifact = getArtifact("EscrowNFT");
    const hashNFT = await walletClient.deployContract({
        abi: nftArtifact.abi,
        bytecode: nftArtifact.bytecode,
        args: [account.address],
    });
    const receiptNFT = await publicClient.waitForTransactionReceipt({ hash: hashNFT });
    const nftAddr = receiptNFT.contractAddress!;
    console.log(`  ✅ EscrowNFT: ${nftAddr}`);

    // 3. EscrowStaking
    console.log("[3/5] Deployando EscrowStaking...");
    const stakingArtifact = getArtifact("EscrowStaking");
    const hashStaking = await walletClient.deployContract({
        abi: stakingArtifact.abi,
        bytecode: stakingArtifact.bytecode,
        args: [tokenAddr, priceFeed, account.address],
    });
    const receiptStaking = await publicClient.waitForTransactionReceipt({ hash: hashStaking });
    const stakingAddr = receiptStaking.contractAddress!;
    console.log(`  ✅ EscrowStaking: ${stakingAddr}`);

    // 4. Transferir Ownership
    console.log("[3.5] Transferindo permissões...");
    const hashTransfer = await walletClient.writeContract({
        address: tokenAddr,
        abi: tokenArtifact.abi,
        functionName: 'transferOwnership',
        args: [stakingAddr],
    });
    await publicClient.waitForTransactionReceipt({ hash: hashTransfer });
    console.log("  ✅ Permissões configuradas");

    // 5. EscrowGovernance
    console.log("[4/5] Deployando EscrowGovernance...");
    const govArtifact = getArtifact("EscrowGovernance");
    const hashGov = await walletClient.deployContract({
        abi: govArtifact.abi,
        bytecode: govArtifact.bytecode,
        args: [tokenAddr, account.address],
    });
    const receiptGov = await publicClient.waitForTransactionReceipt({ hash: hashGov });
    const govAddr = receiptGov.contractAddress!;
    console.log(`  ✅ EscrowGovernance: ${govAddr}`);

    // 6. Escrow (Custodia)
    console.log("[5/5] Deployando Escrow (Custodia)...");
    const escrowArtifact = getArtifact("Escrow");
    const hashEscrow = await walletClient.deployContract({
        abi: escrowArtifact.abi,
        bytecode: escrowArtifact.bytecode,
    });
    const receiptEscrow = await publicClient.waitForTransactionReceipt({ hash: hashEscrow });
    const escrowAddr = receiptEscrow.contractAddress!;
    console.log(`  ✅ Escrow: ${escrowAddr}`);

    // Salvar endereços
    const addresses = {
        network: networkName,
        contracts: {
            EscrowToken: tokenAddr,
            EscrowNFT: nftAddr,
            EscrowStaking: stakingAddr,
            EscrowGovernance: govAddr,
            Escrow: escrowAddr
        }
    };

    const __dirname = dirname(fileURLToPath(import.meta.url));
    writeFileSync(join(__dirname, "..", "deployed-addresses.json"), JSON.stringify(addresses, null, 2));
    console.log("\n📋 Endereços salvos em deployed-addresses.json");
    console.log("\n🚀 DEPLOY FINALIZADO COM SUCESSO!");
}

main().catch(console.error);
