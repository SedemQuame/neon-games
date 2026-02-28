/**
 * TRC20 USDT Transfer — uses triggerSmartContract directly
 * to avoid the "account does not exist" sync issue on trongrid fullNode.
 */
const { TronWeb } = require('tronweb');

const MNEMONIC = 'village attend leader across direct artwork rival near remember edge basic buzz surge fan hint silver vapor rebel identify harvest object best used deny';
const FROM_ADDRESS = 'TKRRiqco4M5ryEb1YmjtzwdRZyAS1mArQk';
const TO_ADDRESS = 'TYnTHdrVK1h6RoVwAmNEhYHXJu4Fhf7c8W';
const USDT_CONTRACT = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const AMOUNT_USDT = 4;

async function main() {
    // Derive key at index 1
    const node = TronWeb.fromMnemonic(MNEMONIC, `m/44'/195'/0'/0/1`);
    const pk = node.privateKey.startsWith('0x') ? node.privateKey.slice(2) : node.privateKey;

    const tronWeb = new TronWeb({ fullHost: 'https://api.trongrid.io', privateKey: pk });

    const hexTo = tronWeb.address.toHex(TO_ADDRESS).replace(/^0x/, '41');
    console.log(`From : ${FROM_ADDRESS}`);
    console.log(`To   : ${TO_ADDRESS} (hex: ${hexTo})`);

    const atomicAmount = AMOUNT_USDT * 1_000_000;
    // Pad to 32 bytes
    const paddedTo = hexTo.replace(/^41/, '000000000000000000000000').padStart(64, '0').slice(-64);
    const paddedAmount = atomicAmount.toString(16).padStart(64, '0');

    // ABI-encoded call: transfer(address,uint256)
    const functionSelector = 'transfer(address,uint256)';
    const parameter = paddedTo + paddedAmount;

    console.log(`\n🚀 Sending ${AMOUNT_USDT} USDT via triggerSmartContract…`);

    const tx = await tronWeb.transactionBuilder.triggerSmartContract(
        USDT_CONTRACT,
        functionSelector,
        { feeLimit: 20_000_000 }, // 20 TRX max fee in sun
        [
            { type: 'address', value: TO_ADDRESS },
            { type: 'uint256', value: atomicAmount },
        ],
        FROM_ADDRESS
    );

    if (!tx.result || !tx.result.result) {
        console.error('❌ triggerSmartContract failed:', tx.result);
        process.exit(1);
    }

    // Sign and broadcast
    const signed = await tronWeb.trx.sign(tx.transaction);
    const receipt = await tronWeb.trx.sendRawTransaction(signed);

    console.log('\n✅ Broadcast result:', JSON.stringify(receipt, null, 2));
    if (receipt.result || receipt.txid) {
        const txid = receipt.txid || receipt.transaction?.txID;
        console.log(`\n   TX ID: ${txid}`);
        console.log(`   View:  https://tronscan.org/#/transaction/${txid}`);
    }
}

main().catch(err => {
    console.error('Error:', err.message || JSON.stringify(err));
    process.exit(1);
});
