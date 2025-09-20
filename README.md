# TinyPay FA - Modern Offline Payment System on Aptos

A next-generation offline payment solution built on the Aptos blockchain using the Fungible Asset (FA) standard, supporting multiple FA tokens for secure and convenient offline transactions between merchants and users.

## 🎯 Overview

TinyPay FA is an innovative offline payment system that leverages Aptos' modern Fungible Asset standard to solve blockchain payment challenges in network-constrained environments. The system features:

- **Fungible Asset Support**: Built on Aptos FA standard for better interoperability and performance
- **Multi-Asset Management**: Support for APT, USDC, and any FA-compliant tokens
- **Offline Payment Vouchers**: Generate cryptographic payment vouchers for offline use
- **Merchant Precommit System**: Secure merchant precommit mechanism for payment validation
- **Hash Chain Security**: SHA256-based tail hash system for anti-replay protection
- **Configurable Limits**: User-defined payment limits and tail update restrictions
- **Dynamic Fee System**: Adjustable transaction fees (default 1%, admin configurable)
- **Resource Account Security**: Isolated fund management through resource accounts

## 🏗️ Architecture

### Core Data Structures

#### UserAccount
```move
struct UserAccount has key {
    balances: Table<address, u64>,    // FA token balances (keyed by metadata address)
    tail: vector<u8>,                 // Current tail hash value (SHA256 bytes)
    payment_limit: u64,               // Maximum payment amount per transaction
    tail_update_count: u64,           // Number of times tail has been updated
    max_tail_updates: u64             // Maximum allowed tail updates
}
```

#### TinyPayState
```move
struct TinyPayState has key {
    total_deposits: Table<address, u64>,      // Total deposits per FA type
    total_withdrawals: Table<address, u64>,   // Total withdrawals per FA type
    fee_rate: u64,                           // Fee rate in basis points (default: 100 = 1%)
    admin: address,                          // Admin address
    paymaster: address,                      // Paymaster address for fee-free operations
    signer_cap: SignerCapability,            // Resource account signer capability
    precommits: Table<vector<u8>, PreCommit>, // Merchant precommit storage
    supported_assets: Table<address, bool>    // Supported FA types (keyed by metadata address)
}
```

#### PreCommit
```move
struct PreCommit has store, drop {
    merchant: address,     // Merchant address
    expiry_time: u64      // Precommit expiry timestamp
}
```

### Public Entry Functions

#### Core Functions
- `add_asset_support(admin: &signer, asset_metadata: Object<Metadata>)` - Add support for a new FA type
- `deposit(user: &signer, asset_metadata: Object<Metadata>, amount: u64, tail: vector<u8>)` - Deposit FA tokens with tail hash
- `withdraw_funds(user: &signer, asset_metadata: Object<Metadata>, amount: u64)` - Withdraw funds from account
- `refresh_tail(user: &signer, new_tail: vector<u8>)` - Update payment tail hash

#### Payment Functions
- `merchant_precommit(merchant: &signer, payer: address, recipient: address, amount: u64, asset_metadata: Object<Metadata>, otp: vector<u8>)` - Merchant precommit for payment
- `complete_payment(caller: &signer, otp: vector<u8>, payer: address, recipient: address, amount: u64, asset_metadata: Object<Metadata>, commit_hash: vector<u8>)` - Complete offline payment

#### User Configuration Functions
- `set_payment_limit(user: &signer, limit: u64)` - Set payment limit for user account
- `set_tail_updates_limit(user: &signer, limit: u64)` - Set tail update limit for user account

### View Functions

- `get_balance(user_address: address, asset_metadata: Object<Metadata>): u64` - Query user balance for specific FA
- `get_user_tail(user_address: address): vector<u8>` - Get user's current tail hash
- `get_user_limits(user_address: address): (u64, u64, u64)` - Get user limits and counts (payment_limit, tail_update_count, max_tail_updates)
- `is_asset_supported(asset_metadata: Object<Metadata>): bool` - Check if FA type is supported
- `get_system_stats(asset_metadata: Object<Metadata>): (u64, u64, u64)` - Get system statistics (total_deposits, total_withdrawals, fee_rate)
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
# Use the automated FA deployment script
chmod +x ./scripts/deploy_fa_system.sh
./scripts/deploy_fa_system.sh testnet testnet

# Or deploy manually
aptos move publish --profile testnet
```

## 📋 Usage Examples

### 1. Add Support for New FA Type
```bash
# Get USDC metadata address
USDC_METADATA=$(aptos move view \
  --function-id <CONTRACT_ADDRESS>::usdc::get_metadata \
  --profile testnet | jq -r '.[]')

# Add USDC support (admin only)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::add_asset_support \
  --args "object:${USDC_METADATA}" --profile testnet
```

### 2. Mint and Deposit FA Tokens
```bash
# First, mint some test USDC (8 decimals)
aptos move run --function-id <CONTRACT_ADDRESS>::usdc::mint \
  --args "address:$(aptos config show-profiles --profile testnet | grep account | awk '{print $2}')" "u64:1000000000" \
  --profile testnet

# Deposit USDC to TinyPay (100 USDC = 10000000000)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::deposit \
  --args "object:${USDC_METADATA}" "u64:10000000000" "vector<u8>:0x696e697469616c5f7461696c" \
  --profile testnet
```

### 3. Generate Payment Hash Chain
```bash
# Use the provided Python script to generate otp/tail parameters
python3 scripts/complete_workflow.py "HelloAptosKS" -n 1000
```

### 4. Merchant Precommit
```bash
# Merchant precommits to a payment
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::merchant_precommit \
  --args "address:0x<PAYER>" "address:0x<RECIPIENT>" "u64:100000000" "object:${USDC_METADATA}" "vector<u8>:0x6f7470" \
  --profile merchant
```

### 5. Complete Payment
```bash
# Complete the offline payment (as paymaster or with valid precommit)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::complete_payment \
  --args "vector<u8>:0x6f7470" "address:0x<PAYER>" "address:0x<RECIPIENT>" "u64:100000000" "object:${USDC_METADATA}" "vector<u8>:0x636f6d6d69745f68617368" \
  --profile testnet
```

### 6. Query Balances
```bash
# Check USDC balance in TinyPay
aptos move view --function-id <CONTRACT_ADDRESS>::tinypay::get_balance \
  --args "address:0x<USER_ADDRESS>" "object:${USDC_METADATA}"

# Check user's wallet USDC balance
aptos account balance --profile testnet
```

### 7. Withdraw Funds
```bash
# Withdraw 50 USDC from TinyPay back to wallet
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::withdraw_funds \
  --args "object:${USDC_METADATA}" "u64:5000000000" --profile testnet
```

### 8. User Configuration
```bash
# Set payment limit (max 1000 USDC per transaction)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::set_payment_limit \
  --args "u64:100000000000" --profile testnet

# Set tail update limit (max 100 updates)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::set_tail_updates_limit \
  --args "u64:100" --profile testnet

# Refresh tail hash
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::refresh_tail \
  --args "vector<u8>:0x6e65775f7461696c" --profile testnet
```


## 🔒 Security Features

- **Hash Chain Verification**: Uses SHA256-based tail hash system for secure payment verification
- **Resource Account Isolation**: Funds are managed through isolated resource accounts
- **Payment Limits**: User-configurable payment limits to prevent large unauthorized transactions
- **Tail Update Limits**: Restricts frequency of tail hash updates to prevent abuse
- **Balance Verification**: All operations verify sufficient balance before execution
- **Admin Controls**: Only admin can add new FA asset support
- **Paymaster System**: Designated paymaster can execute operations without precommit validation
- **Precommit Security**: Merchant precommit system with time-based expiry for additional security
- **FA Standard Compliance**: Built on Aptos Fungible Asset standard for enhanced security and interoperability

## 🧪 Testing

The project includes comprehensive test coverage for:

- ✅ FA token deposit and withdrawal functionality
- ✅ Hash chain generation and verification with tail system
- ✅ Payment limit enforcement and user configuration
- ✅ Merchant precommit and payment completion flows
- ✅ Error handling (insufficient balance, unsupported assets, etc.)
- ✅ Admin functions (asset support, system configuration)
- ✅ USDC FA integration and operations
- ✅ System statistics and balance queries
- ✅ Resource account fund management

Run tests:
```bash
# Run all tests
aptos move test --profile testnet

# Run specific test functions
aptos move test --filter test_deposit --profile testnet
aptos move test --filter test_payment --profile testnet
```

## 📁 Project Structure

```
├── Move.toml                    # Package configuration
├── sources/
│   ├── tinypay.move            # Main TinyPay FA contract
│   └── usdc.move               # Test USDC FA implementation
├── tests/
│   └── tinypay_test.move       # Comprehensive unit tests
├── scripts/
│   ├── deploy_fa_system.sh     # FA system deployment script
│   ├── complete_workflow.py    # Payment workflow generator
│   ├── hex_to_ascii_bytes.py   # Utility for hex conversion
│   ├── setup_usdc.py           # USDC setup automation
│   └── usdc_demo.py            # USDC functionality demo
├── docs/
│   ├── deployment_guide.md     # Complete deployment guide
│   ├── usdc_integration.md     # USDC integration guide
│   ├── usdc_summary.md         # Multi-asset feature summary
│   └── migration_guide.md      # Migration documentation
├── examples/
│   └── usdc_integration_example.md # Usage examples
└── README.md                   # Project documentation
```

## 🎯 Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 1 | `E_INSUFFICIENT_BALANCE` | Insufficient balance for the requested operation |
| 2 | `E_INVALID_AMOUNT` | Invalid amount provided (must be greater than 0) |
| 3 | `E_ACCOUNT_NOT_INITIALIZED` | User account has not been initialized |
| 4 | `E_INVALID_TAIL` | Invalid tail value provided |
| 5 | `E_INVALID_OPT` | Invalid operation type provided |
| 6 | `E_INVALID_PRECOMMIT` | Invalid precommit value provided |
| 7 | `E_NOT_ADMIN` | Only admin can perform this operation |
| 8 | `E_PAYMENT_LIMIT_EXCEEDED` | Payment amount exceeds the configured limit |
| 9 | `E_TAIL_UPDATES_LIMIT_EXCEEDED` | Tail update limit has been exceeded |
| 10 | `E_ASSET_NOT_SUPPORTED` | Fungible asset is not supported |
| 11 | `E_ASSET_ALREADY_SUPPORTED` | Fungible asset is already supported |

## 📊 Events

### AccountInitialized
```move
struct AccountInitialized has drop, store {
    user_address: address
}
```

### DepositMade
```move
struct DepositMade has drop, store {
    user_address: address,
    asset_metadata: address,
    amount: u64,
    tail: vector<u8>,
    new_balance: u64,
    timestamp: u64
}
```

### FundsWithdrawn
```move
struct FundsWithdrawn has drop, store {
    user_address: address,
    asset_metadata: address,
    amount: u64,
    new_balance: u64,
    timestamp: u64
}
```

### PaymentCompleted
```move
struct PaymentCompleted has drop, store {
    payer: address,
    recipient: address,
    asset_metadata: address,
    amount: u64,
    fee: u64,
    new_tail: vector<u8>,
    timestamp: u64
}
```

### AssetSupported
```move
struct AssetSupported has drop, store {
    asset_metadata: address,
    timestamp: u64
}
```

### PreCommitMade
```move
struct PreCommitMade has drop, store {
    merchant_address: address,
    commit_hash: vector<u8>,
    expiry_time: u64,
    timestamp: u64
}
```

### TailRefreshed
```move
struct TailRefreshed has drop, store {
    user_address: address,
    old_tail: vector<u8>,
    new_tail: vector<u8>,
    tail_update_count: u64,
    timestamp: u64
}
```

## 🪙 Supported Assets

### Test USDC FA
- **Module**: `<CONTRACT_ADDRESS>::usdc`
- **Decimals**: 8
- **Unit**: 1 USDC = 100,000,000 units
- **Features**: Mint, burn, transfer, freeze/unfreeze, pause/unpause
- **Metadata**: Obtained via `usdc::get_metadata()`

### Native APT (Future Support)
- **Type**: Can be wrapped as FA for TinyPay compatibility
- **Decimals**: 8
- **Unit**: octas (1 APT = 100,000,000 octas)

### Adding New FA Assets
To add support for additional FA assets:
1. Deploy the FA contract following Aptos FA standard
2. Call `add_asset_support(asset_metadata: Object<Metadata>)` as admin
3. Users can then deposit/withdraw the new FA asset type
4. Ensure the FA contract implements proper metadata and primary store support

## 🔮 Future Enhancements

- **Native APT Support**: Add native APT support through FA wrapper
- **Batch Operations**: Support batch payment processing and bulk operations
- **Cross-Chain Bridge**: Enable cross-chain FA asset transfers and payments
- **Dynamic Fee Structure**: Implement network-based dynamic fee adjustment
- **Mobile SDK**: Develop mobile SDKs for iOS and Android integration
- **Merchant Dashboard**: Build web interface for merchant payment management
- **Advanced Analytics**: Add comprehensive payment analytics and reporting
- **Multi-Signature Support**: Add multi-signature wallet integration
- **Governance Token**: Implement governance token for decentralized system management

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

**TinyPay FA** - Next-generation blockchain payments with Fungible Asset standard 🚀

## 📚 Additional Resources

- **[Complete Deployment Guide](docs/deployment_guide.md)** - Detailed deployment and configuration instructions
- **[FA System Deployment Script](scripts/deploy_fa_system.sh)** - Automated deployment script
- **[Python Workflow Tools](scripts/)** - Helper scripts for payment workflow generation
- **[Test Suite](tests/tinypay_test.move)** - Comprehensive unit tests

For technical support or questions, please check the documentation or open an issue in the repository.
