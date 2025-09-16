# TinyPay - Aptos离线支付系统

一个基于Aptos区块链的离线支付解决方案，为商户和用户提供安全、便捷的单向离线支付功能。

## 🎯 Overview

TinyPay是一个创新的离线支付系统，解决了区块链支付在网络受限环境下的使用难题。系统的核心功能包括：

- **用户存款管理**：用户将APT存入智能合约，系统维护个人余额
- **离线凭证生成**：用户可以离线生成包含金额和过期时间的支付凭证
- **商户资金提取**：商户验证凭证有效性并提取对应资金
- **防重放攻击**：每个凭证都有唯一ID，确保只能使用一次
- **手续费机制**：系统收取1%的交易手续费（可由管理员调整）

## 🏗️ Architecture

### Core Data Structures

#### UserAccount
```move
struct UserAccount has key {
    balance: u64,                            // 可用APT余额（以octas为单位）
    used_vouchers: Table<String, VoucherInfo>, // 已使用凭证追踪
    nonce: u64,                             // 凭证生成随机数
}
```

#### VoucherInfo  
```move
struct VoucherInfo has store, drop {
    amount: u64,        // 凭证金额
    expiry_time: u64,   // 过期时间
    is_redeemed: bool,  // 是否已兑现
}
```

#### TinyPayState
```move
struct TinyPayState has key {
    total_deposits: u64,        // 系统总存款
    total_withdrawals: u64,     // 系统总提取
    fee_rate: u64,             // 手续费率（基点）
    admin: address,            // 管理员地址
    signer_cap: SignerCapability, // 签名权限
}
```

### Public Entry Functions

- `initialize_account(user: &signer)` - 初始化用户账户
- `deposit(user: &signer, amount: u64)` - 存款APT到系统
- `generate_voucher(user: &signer, amount: u64, expiry_seconds: u64)` - 生成支付凭证
- `redeem_voucher(merchant: &signer, user_address: address, voucher_id: String)` - 商户兑现凭证
- `cancel_voucher(user: &signer, voucher_id: String)` - 用户取消未使用凭证
- `update_fee_rate(admin: &signer, new_fee_rate: u64)` - 管理员更新手续费

### View Functions

- `get_balance(user_address: address): u64` - 查询用户余额
- `get_voucher_info(user_address: address, voucher_id: String): (bool, u64, u64, bool)` - 查询凭证信息
- `get_system_stats(): (u64, u64, u64)` - 查询系统统计信息
- `is_account_initialized(user_address: address): bool` - 检查账户是否已初始化
- `get_vault_address(): address` - 获取资金库地址

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

### 1. 初始化账户
```bash
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::initialize_account --profile testnet
```

### 2. 存款APT
```bash
# 存入1 APT (100000000 octas)
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::deposit \
  --args u64:100000000 --profile testnet
```

### 3. 生成支付凭证
```bash
# 生成0.5 APT的凭证，有效期1小时
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::generate_voucher \
  --args u64:50000000 u64:3600 --profile testnet
```

### 4. 商户兑现凭证
```bash
# 从事件日志中获取voucher_id，然后兑现
aptos move run --function-id <CONTRACT_ADDRESS>::tinypay::redeem_voucher \
  --args address:0x<USER_ADDRESS> string:"voucher_<ID>" --profile testnet
```

### 5. 查询余额
```bash
aptos move view --function-id <CONTRACT_ADDRESS>::tinypay::get_balance \
  --args address:0x<USER_ADDRESS>
```


## 🔒 Security Features

- **凭证唯一性**：每个凭证都有唯一ID，防止重复使用
- **时效性控制**：凭证设有过期时间，降低安全风险
- **余额检查**：生成凭证时验证用户余额充足
- **权限控制**：只有管理员可以修改手续费率
- **资金隔离**：使用resource account管理系统资金

## 🧪 Testing

项目包含全面的测试用例，覆盖以下场景：

- ✅ 账户初始化和存款功能
- ✅ 凭证生成和兑现流程
- ✅ 凭证取消和余额恢复
- ✅ 错误场景处理（余额不足、重复使用等）
- ✅ 管理员功能（手续费调整）
- ✅ 系统统计查询

运行测试：
```bash
aptos move test --dev --skip-fetch-latest-git-deps
```

## 📁 Project Structure

```
├── Move.toml                    # 包配置文件
├── sources/
│   └── tinypay.move            # 主合约实现
├── tests/
│   └── tinypay_test.move       # 综合单元测试
├── scripts/
│   └── deploy.sh               # 部署脚本
└── README.md                   # 项目文档
```

## 🎯 Error Codes

| Code | 常量 | 描述 |
|------|------|------|
| 1 | `E_INSUFFICIENT_BALANCE` | 余额不足 |
| 2 | `E_INVALID_AMOUNT` | 无效金额 |
| 3 | `E_VOUCHER_ALREADY_USED` | 凭证已使用 |
| 5 | `E_ACCOUNT_NOT_INITIALIZED` | 账户未初始化 |
| 6 | `E_VOUCHER_EXPIRED` | 凭证已过期 |
| 7 | `E_INVALID_VOUCHER_ID` | 无效凭证ID |
| 8 | `E_NOT_ADMIN` | 不是管理员 |

## 📊 Events

### AccountInitialized
```move
struct AccountInitialized has drop, store {
    user_address: address,
}
```

### DepositMade
```move
struct DepositMade has drop, store {
    user_address: address,
    amount: u64,
    new_balance: u64,
    timestamp: u64,
}
```

### VoucherGenerated
```move
struct VoucherGenerated has drop, store {
    user_address: address,
    voucher_id: String,
    amount: u64,
    expiry_time: u64,
}
```

### VoucherRedeemed
```move
struct VoucherRedeemed has drop, store {
    user_address: address,
    merchant_address: address,
    voucher_id: String,
    amount: u64,
    fee: u64,
    timestamp: u64,
}
```

## 🔮 Future Enhancements

- **数字签名验证**：添加离线签名验证机制提高安全性
- **批量操作**：支持批量生成和兑现凭证
- **多币种支持**：扩展支持其他代币类型
- **动态手续费**：根据网络状况自动调整手续费
- **凭证转账**：允许凭证在用户间转移
- **商户白名单**：建立可信商户验证机制

## 🤝 Contributing

欢迎贡献代码和提出改进建议！请遵循以下步骤：

1. Fork 本项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 License

本项目采用 MIT 许可证 - 详情请见 [LICENSE](LICENSE) 文件。

## 📞 联系方式

如有问题或建议，请通过以下方式联系：

- 项目 Issues: [GitHub Issues](https://github.com/your-username/tinypay/issues)
- 邮箱: your-email@example.com

---

**TinyPay** - 让区块链支付无处不在 🚀
