// userFlows.js
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const { ethers } = require('ethers');
const { VennClient } = require('@vennbuild/venn-dapp-sdk');

// Minimal ABIs we need
const ERC20_ABI = [
    'function approve(address spender, uint256 amount) returns (bool)',
    'function balanceOf(address owner) view returns (uint256)',
    'function decimals() view returns (uint8)',
    'function allowance(address owner, address spender) view returns (uint256)'
];

const COLLATERAL_ABI = [
    'function deposit(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount)',
    'function balances(address account, uint256 optionId) view returns (uint256 baseBalance, uint256 underlyingBalance)',
    'function withdraw(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount)'
];

const ORDERBOOK_ABI = [
    'function make(int256 amount, uint256 price, uint256 expiration) returns (uint256)',
    'function take(uint256 id, int256 amount, uint256 price)',
    'function longOptionId() view returns (uint256)',
    'function status(bool isBid, uint256 id) view returns (int256 amount, uint256 price, uint256 expiration, address owner)',
    'function cancel(bool isBid, uint256 id)'
];

const SCHOLES_OPTION_ABI = [
    'function getExpiration(uint256 optionId) view returns (uint256)',
    'function timeOracle() view returns (address)',
    'function exercise(uint256 optionId, uint256 amount, bytes calldata proof)',
    'function getOpposite(uint256 optionId) view returns (uint256)',
    'function balanceOf(address account, uint256 id) view returns (uint256)'
];

async function main() {
    // Setup
    const provider = new ethers.providers.JsonRpcProvider(process.env.HOLESKY_RPC);
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const signer2 = new ethers.Wallet(process.env.PRIVATE_KEY_2, provider);

    // Setup Venn client
    const vennClient = new VennClient({
        vennURL: process.env.VENN_NODE_URL,
        vennPolicyAddress: process.env.VENN_POLICY_ADDRESS
    });

    // Contract addresses from Holesky deployment
    const ADDRESSES = {
        options: '0x30DC1F6C1b50c9118163504f09C165C891E760d5',
        collaterals: '0xcF9660825e275dEFa91Fa8F344520125AA3d2734',
        orderBook: '0x4661450F8C83274be7cBeBD7dC4489E27D3e085D',
        USDC: '0x2EccD0AeA2317558F03c5758B19F7745f54EA1Ea',
        WETH: '0x026bc390C753F280663472dB16d245156297CCa0'
    };

    // Contracts
    const usdc = new ethers.Contract(ADDRESSES.USDC, ERC20_ABI, signer);
    const weth = new ethers.Contract(ADDRESSES.WETH, ERC20_ABI, signer);
    const collaterals = new ethers.Contract(ADDRESSES.collaterals, COLLATERAL_ABI, signer);
    const orderBook = new ethers.Contract(ADDRESSES.orderBook, ORDERBOOK_ABI, signer);
    const orderBook2 = new ethers.Contract(ADDRESSES.orderBook, ORDERBOOK_ABI, signer2);
    const options = new ethers.Contract(ADDRESSES.options, SCHOLES_OPTION_ABI, signer);

    // Get the option ID from the order book
    const optionId = await orderBook.longOptionId();
    console.log('Using option ID:', optionId);

    // Check option expiration
    const expiration = await options.getExpiration(optionId);
    if (expiration <= Math.floor(Date.now() / 1000)) {
        throw new Error('Option has expired');
    }

    async function logTransaction(tx, description) {
        console.log(`\n${description}`);
        console.log('Transaction hash:', tx.hash);
        const receipt = await tx.wait();
        console.log('Gas used:', receipt.gasUsed.toString());
        console.log('Block number:', receipt.blockNumber);
        return receipt;
    }

    async function approveAndDeposit() {
        console.log('\nStarting approve and deposit flow...');

        // 1. Approve both USDC and WETH
        const usdcAmount = ethers.utils.parseUnits('1000', 6); // 1000 USDC
        const wethAmount = ethers.utils.parseEther('1'); // 1 WETH

        // Normal token approvals (no need to demonstrate bypass)
        const usdcApprovalTx = await usdc.populateTransaction.approve(ADDRESSES.collaterals, usdcAmount);
        const approvedUsdcTx = await vennClient.approve({
            from: await signer.getAddress(),
            to: ADDRESSES.USDC,
            data: usdcApprovalTx.data,
            value: '0'
        });
        await logTransaction(
            await signer.sendTransaction(approvedUsdcTx),
            'USDC Approval Transaction'
        );

        // Approve WETH
        const wethApprovalTx = await weth.populateTransaction.approve(ADDRESSES.collaterals, wethAmount);
        const approvedWethTx = await vennClient.approve({
            from: await signer.getAddress(),
            to: ADDRESSES.WETH,
            data: wethApprovalTx.data,
            value: '0'
        });
        await logTransaction(
            await signer.sendTransaction(approvedWethTx),
            'WETH Approval Transaction'
        );

        // 2. Try deposit without Venn SDK (should fail)
        try {
            console.log('\nTrying deposit without Venn protection (should fail)...');
            const tx = await signer.sendTransaction({
                to: ADDRESSES.collaterals,
                data: collaterals.interface.encodeFunctionData('deposit', [
                    optionId,
                    usdcAmount,
                    wethAmount
                ]),
                gasLimit: 1000000 // Force it through with manual gas limit
            });
            await logTransaction(tx, 'Unprotected Deposit Transaction (Expected to Fail)');
        } catch (error) {
            console.log('Expected failure received:', error.message);
        }

        // Now deposit properly with Venn SDK
        const depositTx = await collaterals.populateTransaction.deposit(
            optionId,
            usdcAmount,
            wethAmount
        );

        const approvedDepositTx = await vennClient.approve({
            from: await signer.getAddress(),
            to: ADDRESSES.collaterals,
            data: depositTx.data,
            value: '0'
        });

        await logTransaction(
            await signer.sendTransaction(approvedDepositTx),
            'Protected Deposit Transaction'
        );
    }

    try {
        console.log('Starting script with address:', await signer.getAddress());

        // Step 1: Approve and deposit collateral
        console.log('\n=== Step 1: Approve and Deposit ===');
        await approveAndDeposit();



        console.log('\nScript completed successfully - all operations executed');
    } catch (error) {
        console.error('\nError:', error);
        console.error('Error details:', error.message);
    }
}

main().catch(console.error);