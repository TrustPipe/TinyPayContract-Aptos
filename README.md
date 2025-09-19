# TinyPay - Multi-Coin Offline Payment System on Aptos

A comprehensive offline payment solution built on the Aptos blockchain, supporting multiple cryptocurrencies for secure and convenient offline transactions between merchants and users.

## 🎯 Overview

TinyPay is an innovative offline payment system that solves the challenge of blockchain payments in network-constrained environments. The system now supports multiple coin types and includes:

- **Multi-Coin Support**: Support for APT, USDC, and other custom tokens
- **User Deposit Management**: Users can deposit various cryptocurrencies into smart contracts
- **Offline Payment Generation**: Users can generate offline payment credentials with amounts and expiry times
- **Merchant Fund Extraction**: Merchants can verify credentials and extract corresponding funds
- **Anti-Replay Protection**: Each credential has a unique ID ensuring single-use only
- **Dynamic Fee System**: Configurable transaction fees (default 1%, adjustable by admin)
- **Secure Hash Chain**: Uses iterative SHA256 hashing for payment verification

## 🏗️ Architecture

### Core Data Structures

#### UserAccount
```move
struct UserAccount has key {
    balances: Table<TypeInfo, u64>,           // Multi-coin balances by type
    tail_hashes: Table<TypeInfo, vector<u8>>, // Payment tail hashes per coin type
    payment_limits: Table<TypeInfo, u64>,     // Payment limits per coin type
    tail_update_limits: Table<TypeInfo, u64>, // Tail update limits per coin type
    tail_update_counts: Table<TypeInfo, u64>, // Current tail update counts
}
```

#### TinyPayState
```move
struct TinyPayState has key {
    admin: address,                           // Admin address
    paymaster: address,                       // Paymaster address for fee-free operations
    fee_rate: u64,                           // Fee rate in basis points (default: 100 = 1%)
    supported_coins: Table<TypeInfo, bool>,   // Supported coin types
    total_deposits: Table<TypeInfo, u64>,     // Total deposits per coin type
    total_withdrawals: Table<TypeInfo, u64>,  // Total withdrawals per coin type
    precommits: Table<vector<u8>, PrecommitInfo>, // Merchant precommit storage
    signer_cap: SignerCapability,            // Resource account signer capability
}
```

#### PrecommitInfo
```move
struct PrecommitInfo has store, drop {
    payer: address,        // Payment sender
    recipient: address,    // Payment recipient
    amount: u64,          // Payment amount
    coin_type: TypeInfo,  // Coin type for payment
    expiry_time: u64,     // Precommit expiry timestamp
}
```

### Public Entry Functions

#### Core Functions
- `add_coin_support<CoinType>(admin: &signer)` - Add support for a new coin type
- `deposit<CoinType>(user: &signer, amount: u64, tail: vector<u8>)` - Deposit coins with tail hash
- `withdraw_funds<CoinType>(user: &signer, amount: u64)` - Withdraw funds from account
- `refresh_tail<CoinType>(user: &signer, new_tail: vector<u8>)` - Update payment tail hash

#### Payment Functions
- `merchant_precommit<CoinType>(merchant: &signer, payer: address, recipient: address, amount: u64, opt: vector<u8>)` - Merchant precommit for payment
- `complete_payment<CoinType>(caller: &signer, opt: vector<u8>, payer: address, recipient: address, amount: u64, commit_hash: vector<u8>)` - Complete offline payment

#### Admin Functions
- `set_fee_rate(admin: &signer, new_fee_rate: u64)` - Update system fee rate
- `set_payment_limit<CoinType>(user: &signer, limit: u64)` - Set payment limit for coin type
- `set_tail_updates_limit<CoinType>(user: &signer, limit: u64)` - Set tail update limit

### View Functions

- `get_balance<CoinType>(user_address: address): u64` - Query user balance for specific coin
- `get_user_tail<CoinType>(user_address: address): vector<u8>` - Get user's current tail hash
- `get_user_limits<CoinType>(user_address: address): (u64, u64, u64)` - Get user limits and counts
- `is_coin_supported<CoinType>(): bool` - Check if coin type is supported
- `get_system_stats<CoinType>(): (u64, u64)` - Get system deposit/withdrawal statistics
- `bytes_to_hex_ascii(bytes: vector<u8>): vector<u8>` - Convert bytes to hex ASCII representation

## 🚀 Quick Start

### Prerequisites

1. Install [Aptos CLI](https://aptos.dev/tools/aptos-cli/install-cli/)
2. Set up a testnet profile:
   ```bash
   aptos init --profile testnet --network testnet
   ```
3. Fund your account with test APT:
   ```bash
   aptos account fund-with-faucet --profile testnet
   ```

### Compilation and Testing

```bash
# Compile the contract
aptos move compile --dev

# Run all tests
aptos move test --dev --skip-fetch-latest-git-deps

# Run specific test
aptos move test --filter test_pay --dev --skip-fetch-latest-git-deps
```

### Deployment

```bash
# Use the provided script
chmod +x ./scripts/deploy.sh
./scripts/deploy.sh

# Or deploy manually
aptos move publish --profile testnet
```

## 📋 Usage Examples

### 1. Add Support for New Coin Type
```bash
# Add USDC support (admin only)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::add_coin_support \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC --profile testnet
```

### 2. Deposit Coins
```bash
# Deposit 1000 USDC (6 decimals = 1000000000 units)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::deposit \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC \
  --args u64:1000000000 "u8:[97,100,98,54,...]" --profile testnet

# Deposit 1 APT (8 decimals = 100000000 octas)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::deposit \
  --type-args 0x1::aptos_coin::AptosCoin \
  --args u64:100000000 "u8:[97,100,98,54,...]" --profile testnet
```

### 3. Generate Payment Hash Chain
```bash
# Use the provided Python script to generate opt/tail parameters
python3 scripts/complete_workflow.py "HelloAptosKS" -n 1000
```

### 4. Merchant Precommit
```bash
# Merchant precommits to a payment
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::merchant_precommit \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC \
  --args address:0x<PAYER> address:0x<RECIPIENT> u64:10000000 "u8:[56,52,101,...]" --profile testnet
```

### 5. Complete Payment
```bash
# Complete the offline payment (as paymaster or with valid precommit)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::complete_payment \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC \
  --args "u8:[56,52,101,...]" address:0x<PAYER> address:0x<RECIPIENT> u64:10000000 "u8:[0]" --profile testnet
```

### 6. Query Balances
```bash
# Check USDC balance
aptos move view --function-id <CONTRACT_ADDRESS>::tinypay::get_balance \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC \
  --args address:0x<USER_ADDRESS>

# Check APT balance
aptos move view --function-id <CONTRACT_ADDRESS>::tinypay::get_balance \
  --type-args 0x1::aptos_coin::AptosCoin \
  --args address:0x<USER_ADDRESS>
```

### 7. Withdraw Funds
```bash
# Withdraw 500 USDC
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::withdraw_funds \
  --type-args <CONTRACT_ADDRESS>::test_usdc::TestUSDC \
  --args u64:500000000 --profile testnet
```


## 🔒 Security Features

- **Hash Chain Verification**: Uses iterative SHA256 hashing for secure payment verification
- **Multi-Coin Isolation**: Each coin type has separate balance and limit management
- **Payment Limits**: Configurable payment limits per coin type to prevent large unauthorized transactions
- **Tail Update Limits**: Restricts frequency of tail hash updates to prevent abuse
- **Balance Verification**: All operations verify sufficient balance before execution
- **Admin Controls**: Only admin can add new coin support and modify system parameters
- **Paymaster System**: Designated paymaster can execute fee-free operations
- **Resource Account**: Uses resource account for secure fund management and isolation

## 🧪 Testing

The project includes comprehensive test coverage for:

- ✅ Multi-coin deposit and withdrawal functionality
- ✅ Hash chain generation and verification
- ✅ Payment limit enforcement
- ✅ Merchant precommit and payment completion flows
- ✅ Error handling (insufficient balance, unsupported coins, etc.)
- ✅ Admin functions (fee adjustment, coin support)
- ✅ USDC integration and mixed coin operations
- ✅ System statistics and balance queries

Run tests:
```bash
# Run all tests
aptos move test --skip-fetch-latest-git-deps

# Run specific test suites
aptos move test --filter usdc --skip-fetch-latest-git-deps
aptos move test --filter mixed --skip-fetch-latest-git-deps
```

## 📁 Project Structure

```
├── Move.toml                    # Package configuration
├── sources/
│   ├── tinypay.move            # Main TinyPay contract
│   └── test_usdc.move          # Test USDC token implementation
├── tests/
│   └── tinypay_test.move       # Comprehensive unit tests
├── scripts/
│   ├── deploy.sh               # Deployment script
│   ├── complete_workflow.py    # Payment workflow generator
│   ├── hex_to_ascii_bytes.py   # Utility for hex conversion
│   ├── setup_usdc.py           # USDC setup automation
│   └── usdc_demo.py            # USDC functionality demo
├── docs/
│   ├── usdc_integration.md     # USDC integration guide
│   ├── usdc_summary.md         # Multi-coin feature summary
│   └── migration_guide.md      # Migration documentation
├── examples/
│   └── usdc_integration_example.md # Usage examples
└── README.md                   # Project documentation
```

## 🎯 Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1 | `E_INSUFFICIENT_BALANCE` | Insufficient balance |
| 2 | `E_INVALID_AMOUNT` | Invalid amount |
| 3 | `E_ACCOUNT_ALREADY_INITIALIZED` | Account already initialized |
| 4 | `E_INVALID_TAIL_HASH` | Invalid tail hash |
| 5 | `E_ACCOUNT_NOT_INITIALIZED` | Account not initialized |
| 6 | `E_PAYMENT_LIMIT_EXCEEDED` | Payment limit exceeded |
| 7 | `E_TAIL_UPDATE_LIMIT_EXCEEDED` | Tail update limit exceeded |
| 8 | `E_NOT_ADMIN` | Not admin |
| 9 | `E_INVALID_PRECOMMIT` | Invalid precommit |
| 10 | `E_COIN_NOT_SUPPORTED` | Coin type not supported |
| 11 | `E_COIN_ALREADY_SUPPORTED` | Coin type already supported |

## 📊 Events

### DepositMade
```move
struct DepositMade has drop, store {
    user_address: address,
    coin_type: String,
    amount: u64,
    tail: vector<u8>,
    new_balance: u64,
    timestamp: u64,
}
```

### WithdrawalMade
```move
struct WithdrawalMade has drop, store {
    user_address: address,
    coin_type: String,
    amount: u64,
    new_balance: u64,
    timestamp: u64,
}
```

### PaymentCompleted
```move
struct PaymentCompleted has drop, store {
    payer: address,
    recipient: address,
    coin_type: String,
    amount: u64,
    fee: u64,
    opt: vector<u8>,
    timestamp: u64,
}
```

### TailUpdated
```move
struct TailUpdated has drop, store {
    user_address: address,
    coin_type: String,
    new_tail: vector<u8>,
    timestamp: u64,
}
```

## 🪙 Supported Tokens

### Native APT
- **Type**: `0x1::aptos_coin::AptosCoin`
- **Decimals**: 8
- **Unit**: octas (1 APT = 100,000,000 octas)

### Test USDC
- **Type**: `<CONTRACT_ADDRESS>::test_usdc::TestUSDC`
- **Decimals**: 6
- **Unit**: micro-USDC (1 USDC = 1,000,000 units)
- **Features**: Mint, burn, transfer, batch operations

### Adding New Tokens
To add support for additional tokens:
1. Implement the token contract following Aptos Coin standard
2. Call `add_coin_support<NewCoinType>()` as admin
3. Users can then deposit/withdraw the new token type

## 🔮 Future Enhancements

- **Digital Signature Verification**: Add offline signature verification for enhanced security
- **Batch Operations**: Support batch payment processing and bulk operations
- **Cross-Chain Bridge**: Enable cross-chain token transfers and payments
- **Dynamic Fee Structure**: Implement network-based dynamic fee adjustment
- **Mobile SDK**: Develop mobile SDKs for iOS and Android integration
- **Merchant Dashboard**: Build web interface for merchant payment management
- **Advanced Analytics**: Add comprehensive payment analytics and reporting

## 🤝 Contributing

We welcome contributions and suggestions! Please follow these steps:

1. Fork the project
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📞 Contact

For questions or suggestions, please reach out through:

- Project Issues: [GitHub Issues](https://github.com/TrustPipe/TinyPayContract-Aptos/issues)
- Documentation: Check the `/docs` folder for detailed guides

---

**TinyPay** - Making blockchain payments accessible everywhere 🚀
