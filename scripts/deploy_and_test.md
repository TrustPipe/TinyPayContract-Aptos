# TinyPay 部署和测试指南

这是一个完整的 TinyPay 离线支付系统部署和交互指南。

## 前置条件

1. **安装 Aptos CLI**: https://aptos.dev/tools/aptos-cli/install-cli/
2. **配置 Aptos 测试网profile**

```bash
# 初始化新的测试网profile
aptos init --profile testnet --network testnet

# 或者配置现有profile
aptos config set-global-config --config-type workspace
```

3. **获取测试网 APT 代币**
```bash
# 从水龙头获取测试APT
aptos account fund-with-faucet --profile testnet
```

## 本地开发和测试

### 1. 编译合约
```bash
# 开发模式编译
aptos move compile --dev --skip-fetch-latest-git-deps
```

### 2. 运行所有单元测试
```bash
# 运行完整测试套件
aptos move test --dev --skip-fetch-latest-git-deps
```

### 3. 运行特定测试
```bash
# 测试存款功能
aptos move test --filter test_deposit --dev --skip-fetch-latest-git-deps

# 测试凭证生成和兑现
aptos move test --filter test_generate_and_redeem_voucher --dev --skip-fetch-latest-git-deps

# 测试余额不足场景
aptos move test --filter test_generate_voucher_insufficient_balance --dev --skip-fetch-latest-git-deps
```

## 部署到测试网

### 1. 发布合约
```bash
aptos move publish --profile testnet
```

### 2. 记录合约地址
部署成功后，请记录输出中的合约地址，后续交互需要用到。

示例输出：
```json
{
  "Result": {
    "transaction_hash": "0x...",
    "gas_used": 1234,
    "success": true,
    "events": [...],
    "changes": [
      {
        "address": "0x123abc...",  // 这是你的合约地址
        "data": {...}
      }
    ]
  }
}
```

## 与合约交互

### 1. 初始化用户账户
```bash
# 每个用户首次使用前需要初始化账户
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::initialize_account \
  --profile testnet
```

### 2. 存入 APT 到系统
```bash
# 存入 1 APT (100000000 octas)
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::deposit \
  --args u64:100000000 \
  --profile testnet

# 存入 0.5 APT (50000000 octas)
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::deposit \
  --args u64:50000000 \
  --profile testnet
```

### 3. 生成支付凭证
```bash
# 生成 0.1 APT 的凭证，有效期 1 小时 (3600秒)
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::generate_voucher \
  --args u64:10000000 u64:3600 \
  --profile testnet

# 生成 0.5 APT 的凭证，有效期 30 分钟 (1800秒)
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::generate_voucher \
  --args u64:50000000 u64:1800 \
  --profile testnet
```

**注意**: 生成凭证后，请从事件日志中记录 `voucher_id`，兑现时需要用到。

### 4. 商户兑现凭证
```bash
# 商户兑现用户的支付凭证
# 需要用户地址和凭证ID
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::redeem_voucher \
  --args address:0x<USER_ADDRESS> string:"voucher_1234567890" \
  --profile testnet
```

### 5. 取消未使用的凭证
```bash
# 用户可以取消自己未使用的凭证，恢复余额
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::cancel_voucher \
  --args string:"voucher_1234567890" \
  --profile testnet
```

### 6. 管理员更新手续费率
```bash
# 管理员将手续费率调整为 0.5% (50 基点)
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::update_fee_rate \
  --args u64:50 \
  --profile testnet
```

## 查询函数

### 查询用户余额
```bash
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::get_balance \
  --args address:0x<USER_ADDRESS>
```

### 查询凭证信息
```bash
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::get_voucher_info \
  --args address:0x<USER_ADDRESS> string:"voucher_1234567890"
```

### 查询系统统计
```bash
# 返回: (总存款, 总提取, 手续费率)
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::get_system_stats
```

### 检查账户是否已初始化
```bash
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::is_account_initialized \
  --args address:0x<USER_ADDRESS>
```

### 获取资金库地址
```bash
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::get_vault_address
```

## 完整使用流程示例

### 场景：用户小明向商户小红支付 0.2 APT

1. **用户小明 (0x100) 初始化账户**
```bash
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::initialize_account \
  --profile ming
```

2. **小明存入 1 APT**
```bash
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::deposit \
  --args u64:100000000 \
  --profile ming
```

3. **小明生成 0.2 APT 的支付凭证**
```bash
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::generate_voucher \
  --args u64:20000000 u64:3600 \
  --profile ming
```

4. **记录事件中的 voucher_id**
从交易事件中获取 `VoucherGenerated` 事件的 `voucher_id`

5. **商户小红 (0x200) 兑现凭证**
```bash
aptos move run \
  --function-id <CONTRACT_ADDR>::tinypay::redeem_voucher \
  --args address:0x100 string:"voucher_<ID>" \
  --profile hong
```

6. **验证结果**
```bash
# 查询小明余额 (应该减少 0.2 APT)
aptos move view \
  --function-id <CONTRACT_ADDR>::tinypay::get_balance \
  --args address:0x100

# 查询小红的钱包余额 (应该增加约 0.198 APT，扣除1%手续费)
aptos account balance --profile hong
```

## 错误处理和故障排除

### 常见错误码

| 错误码 | 常量 | 解决方案 |
|--------|------|----------|
| 1 | `E_INSUFFICIENT_BALANCE` | 检查账户余额是否足够 |
| 2 | `E_INVALID_AMOUNT` | 确保金额大于 0 |
| 3 | `E_VOUCHER_ALREADY_USED` | 凭证已被使用，无法重复兑现 |
| 5 | `E_ACCOUNT_NOT_INITIALIZED` | 先调用 `initialize_account` |
| 6 | `E_VOUCHER_EXPIRED` | 凭证已过期，无法兑现 |
| 7 | `E_INVALID_VOUCHER_ID` | 检查凭证ID是否正确 |
| 8 | `E_NOT_ADMIN` | 只有管理员可以执行此操作 |

### 常见问题

1. **编译错误**: 
   - 检查 Move.toml 依赖项
   - 使用 `--dev --skip-fetch-latest-git-deps` 标志

2. **Gas 费用不足**: 
   - 确保账户有足够的 APT 支付交易费用
   - 使用水龙头获取测试 APT

3. **凭证兑现失败**:
   - 检查凭证是否已过期
   - 确认凭证 ID 正确
   - 验证用户地址正确

4. **权限问题**:
   - 只有账户所有者可以生成/取消自己的凭证
   - 只有管理员可以更新手续费率

### 实用命令

```bash
# 查看账户余额
aptos account balance --profile testnet

# 从水龙头获取测试APT
aptos account fund-with-faucet --profile testnet

# 查看交易状态
aptos transaction show --transaction-hash <TX_HASH>

# 查看账户资源
aptos account list --query resources --account <ACCOUNT_ADDR>

# 查看交易事件
aptos event get-events-by-event-handle \
  --address <CONTRACT_ADDR> \
  --event-handle-struct "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>" \
  --event-handle-field "deposit_events"
```

## 监控和日志

### 重要事件

系统会发出以下事件，可用于监控：

- `AccountInitialized`: 账户初始化
- `DepositMade`: 用户存款
- `VoucherGenerated`: 凭证生成
- `VoucherRedeemed`: 凭证兑现
- `VoucherCancelled`: 凭证取消

### 查看事件日志

```bash
# 查看最近的交易事件
aptos transaction show --transaction-hash <TX_HASH>

# 查看账户相关事件
aptos account list --query events --account <ACCOUNT_ADDR>
```

## 生产环境部署注意事项

1. **主网部署**: 将 `--profile testnet` 替换为 `--profile mainnet`
2. **安全审计**: 生产前进行完整的安全审计
3. **Gas 优化**: 监控和优化 Gas 使用
4. **错误处理**: 实现完善的错误处理和用户反馈
5. **监控告警**: 设置系统监控和异常告警
