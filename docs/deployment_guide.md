# TinyPay FA 系统部署和配置指导文档

## 概述

TinyPay FA 是基于 Aptos Fungible Asset (FA) 标准构建的现代化离线支付系统。本文档提供完整的部署、配置和使用指导。

## 系统架构

### 核心组件

1. **TinyPay 主合约** (`tinypay::tinypay`)
   - 管理用户账户和余额
   - 处理离线支付凭证
   - 支持多种 FA 代币

2. **测试 USDC 合约** (`tinypay::usdc`)
   - 提供测试用的 USDC FA 代币
   - 支持铸造、转账、销毁等操作

### 数据结构

#### UserAccount
```move
struct UserAccount has key {
    balances: Table<address, u64>,    // FA 代币余额 (按 metadata 地址索引)
    tail: vector<u8>,                 // 当前尾部哈希值
    payment_limit: u64,               // 单次支付限额
    tail_update_count: u64,           // 尾部更新次数
    max_tail_updates: u64             // 最大尾部更新次数
}
```

#### TinyPayState
```move
struct TinyPayState has key {
    total_deposits: Table<address, u64>,      // 各 FA 类型总存款
    total_withdrawals: Table<address, u64>,   // 各 FA 类型总提取
    fee_rate: u64,                           // 手续费率 (基点)
    admin: address,                          // 管理员地址
    paymaster: address,                      // 支付主管地址
    signer_cap: SignerCapability,            // 资源账户签名能力
    precommits: Table<vector<u8>, PreCommit>, // 商户预提交
    supported_assets: Table<address, bool>    // 支持的 FA 类型
}
```

## 部署前准备

### 1. 环境要求

- **Aptos CLI**: 版本 >= 3.0.0
- **jq**: JSON 处理工具
- **Python 3**: 用于辅助脚本
- **Git**: 代码管理

### 2. 安装依赖

```bash
# 安装 Aptos CLI
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3

# 安装 jq (macOS)
brew install jq

# 安装 jq (Ubuntu)
sudo apt-get install jq

# 验证安装
aptos --version
jq --version
```

### 3. 配置 Aptos Profile

```bash
# 创建测试网 profile
aptos init --profile testnet --network testnet

# 创建主网 profile (生产环境)
aptos init --profile mainnet --network mainnet

# 获取测试网代币
aptos account fund-with-faucet --profile testnet
```

## 快速部署

### 使用自动化脚本

```bash
# 克隆项目
git clone <repository-url>
cd tinyPay

# 赋予执行权限
chmod +x scripts/deploy_fa_system.sh

# 部署到测试网
./scripts/deploy_fa_system.sh testnet testnet

# 部署到主网 (生产环境)
./scripts/deploy_fa_system.sh mainnet mainnet
```

### 手动部署步骤

#### 1. 编译合约

```bash
# 编译所有合约
aptos move compile --profile testnet

# 验证编译结果
ls -la build/
```

#### 2. 运行测试

```bash
# 运行完整测试套件
aptos move test --profile testnet

# 运行特定测试
aptos move test --filter test_deposit --profile testnet
```

#### 3. 发布合约

```bash
# 发布到测试网
aptos move publish --profile testnet --assume-yes

# 记录合约地址
CONTRACT_ADDRESS=$(aptos config show-profiles --profile testnet | grep account | awk '{print $2}')
echo "Contract deployed at: $CONTRACT_ADDRESS"
```

#### 4. 初始化系统

```bash
# 初始化 TinyPay 系统 (自动调用)
# 系统会在模块部署时自动初始化

# 初始化测试 USDC
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::usdc::init_module" \
    --profile testnet \
    --assume-yes
```

#### 5. 添加资产支持

```bash
# 获取 USDC metadata 地址
USDC_METADATA=$(aptos move view \
    --function-id "${CONTRACT_ADDRESS}::usdc::get_metadata" \
    --profile testnet | jq -r '.[]')

# 添加 USDC 支持
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::add_asset_support" \
    --args "object:${USDC_METADATA}" \
    --profile testnet \
    --assume-yes
```

## 配置管理

### 1. 管理员功能

#### 添加新资产支持

```bash
# 添加新的 FA 资产支持
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::add_asset_support" \
    --args "object:<ASSET_METADATA_ADDRESS>" \
    --profile testnet
```

#### 设置系统参数

```bash
# 更新手续费率 (例如: 1.5% = 150 基点)
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::set_fee_rate" \
    --args "u64:150" \
    --profile testnet
```

### 2. 用户配置

#### 设置支付限额

```bash
# 设置单次支付限额 (例如: 1000 USDC = 1000000000)
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::set_payment_limit" \
    --args "u64:1000000000" \
    --profile testnet
```

#### 设置尾部更新限制

```bash
# 设置最大尾部更新次数 (例如: 100 次)
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::set_tail_updates_limit" \
    --args "u64:100" \
    --profile testnet
```

## 基本使用流程

### 1. 用户存款

```bash
# 存入 USDC (需要先铸造 USDC)
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::usdc::mint" \
    --args "address:$(aptos config show-profiles --profile testnet | grep account | awk '{print $2}')" "u64:1000000000" \
    --profile testnet

# 存入到 TinyPay 系统
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::deposit" \
    --args "object:${USDC_METADATA}" "u64:100000000" "vector<u8>:0x696e697469616c5f7461696c" \
    --profile testnet
```

### 2. 商户预提交

```bash
# 商户预提交支付请求
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::merchant_precommit" \
    --args "address:<PAYER_ADDRESS>" "address:<RECIPIENT_ADDRESS>" "u64:10000000" "object:${USDC_METADATA}" "vector<u8>:0x6f7470" \
    --profile merchant
```

### 3. 完成支付

```bash
# 完成离线支付
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::complete_payment" \
    --args "vector<u8>:0x6f7470" "address:<PAYER_ADDRESS>" "address:<RECIPIENT_ADDRESS>" "u64:10000000" "object:${USDC_METADATA}" "vector<u8>:0x636f6d6d69745f68617368" \
    --profile testnet
```

### 4. 提取资金

```bash
# 用户提取资金回钱包
aptos move run \
    --function-id "${CONTRACT_ADDRESS}::tinypay::withdraw_funds" \
    --args "object:${USDC_METADATA}" "u64:50000000" \
    --profile testnet
```

## 查询功能

### 1. 余额查询

```bash
# 查询用户在 TinyPay 中的 USDC 余额
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::get_balance" \
    --args "address:<USER_ADDRESS>" "object:${USDC_METADATA}"
```

### 2. 系统统计

```bash
# 查询系统统计信息 (总存款, 总提取, 手续费率)
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::get_system_stats" \
    --args "object:${USDC_METADATA}"
```

### 3. 用户限制查询

```bash
# 查询用户限制 (支付限额, 尾部更新次数, 最大更新次数)
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::get_user_limits" \
    --args "address:<USER_ADDRESS>"
```

### 4. 资产支持查询

```bash
# 检查资产是否被支持
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::is_asset_supported" \
    --args "object:${USDC_METADATA}"
```

## 安全考虑

### 1. 权限管理

- **管理员权限**: 只有管理员可以添加新资产支持
- **用户权限**: 用户只能操作自己的账户
- **商户权限**: 商户可以预提交支付请求

### 2. 资金安全

- **资源账户**: 使用资源账户管理资金，提高安全性
- **余额验证**: 所有操作都会验证余额充足性
- **限额控制**: 支持设置支付限额防止大额误操作

### 3. 防重放攻击

- **尾部哈希**: 使用尾部哈希防止支付重放
- **预提交机制**: 商户预提交增加支付安全性
- **时间限制**: 预提交有时间限制防止过期使用

## 监控和维护

### 1. 事件监控

系统会发出以下重要事件：

- `AccountInitialized`: 账户初始化
- `DepositMade`: 用户存款
- `PaymentCompleted`: 支付完成
- `FundsWithdrawn`: 资金提取
- `AssetSupported`: 新资产支持

### 2. 日志查询

```bash
# 查看交易详情
aptos transaction show --transaction-hash <TX_HASH>

# 查看账户资源
aptos account list --query resources --account <ACCOUNT_ADDRESS>
```

### 3. 健康检查

```bash
# 检查合约状态
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::get_system_stats" \
    --args "object:${USDC_METADATA}"

# 验证资产支持
aptos move view \
    --function-id "${CONTRACT_ADDRESS}::tinypay::is_asset_supported" \
    --args "object:${USDC_METADATA}"
```

## 故障排除

### 常见错误

| 错误码 | 常量 | 解决方案 |
|--------|------|----------|
| 1 | `E_INSUFFICIENT_BALANCE` | 检查余额是否充足 |
| 2 | `E_INVALID_AMOUNT` | 确保金额大于 0 |
| 3 | `E_ACCOUNT_NOT_INITIALIZED` | 先进行存款操作自动初始化 |
| 4 | `E_INVALID_TAIL` | 检查尾部哈希格式 |
| 7 | `E_NOT_ADMIN` | 确认管理员权限 |
| 10 | `E_ASSET_NOT_SUPPORTED` | 先添加资产支持 |
| 11 | `E_ASSET_ALREADY_SUPPORTED` | 资产已经支持，无需重复添加 |

### 调试技巧

1. **使用 `--assume-yes` 标志**: 自动确认交易
2. **检查 Gas 费用**: 确保账户有足够的 APT
3. **验证参数格式**: 特别注意 `vector<u8>` 和 `object` 参数
4. **查看事件日志**: 从事件中获取详细信息
5. **重复部署处理**: 如果看到 `E_ASSET_ALREADY_SUPPORTED` 错误，说明资产支持已经添加成功，可以忽略此错误

## 生产环境部署

### 1. 安全检查清单

- [ ] 完成安全审计
- [ ] 测试网充分测试
- [ ] 备份管理员私钥
- [ ] 设置监控告警
- [ ] 准备应急响应计划

### 2. 性能优化

- [ ] Gas 使用优化
- [ ] 批量操作支持
- [ ] 缓存策略
- [ ] 负载均衡

### 3. 运维准备

- [ ] 监控仪表板
- [ ] 日志聚合
- [ ] 备份策略
- [ ] 升级计划

## 总结

TinyPay FA 系统提供了一个安全、高效的离线支付解决方案。通过本指导文档，您可以：

1. 成功部署系统到测试网或主网
2. 正确配置各种参数和权限
3. 理解基本的使用流程
4. 进行有效的监控和维护

如有问题，请参考故障排除部分或联系技术支持。
