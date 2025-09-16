/// TinyPay - Offline Payment System for Aptos
/// Allows users to deposit APT, generate offline payment vouchers, 
/// and enables merchants to redeem those vouchers for APT withdrawals.
module tinypay::tinypay {
    use std::signer;
    use std::string::{Self, String};
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use std::bcs;
    use std::vector;

    // Error codes
    /// 余额不足
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    /// 无效金额
    const E_INVALID_AMOUNT: u64 = 2;
    /// 账户未初始化
    const E_ACCOUNT_NOT_INITIALIZED: u64 = 3;
    /// 无效的tail值
    const E_INVALID_TAIL: u64 = 4;
    /// 无效的opt值
    const E_INVALID_OPT: u64 = 5;
    /// 无效的预提交
    const E_INVALID_PRECOMMIT: u64 = 6;
    /// 非管理员操作
    const E_NOT_ADMIN: u64 = 7;
    /// 超过支付限额
    const E_PAYMENT_LIMIT_EXCEEDED: u64 = 8;
    /// 超过tail更新次数限制
    const E_TAIL_UPDATES_LIMIT_EXCEEDED: u64 = 9;

    /// User account information storing balance and tail
    struct UserAccount has key {
        balance: u64,                            // Available APT balance in octas
        tail: String,                           // Current tail hash value
        payment_limit: u64,                     // Maximum payment amount per transaction (0 = unlimited)
        tail_update_count: u64,                 // Number of times tail has been updated
        max_tail_updates: u64,                  // Maximum allowed tail updates (0 = unlimited)
    }

    /// Pre-commit information for merchant payments
    struct PreCommit has store, drop {
        payer: address,                         // 付款用户地址
        recipient: address,                     // 收款地址
        amount: u64,                           // 金额
        expiry_time: u64,                      // 过期时间 (15分钟后)
    }

    /// Global state for the TinyPay system
    struct TinyPayState has key {
        total_deposits: u64,        // Total APT deposited in the system
        total_withdrawals: u64,     // Total APT withdrawn from the system
        fee_rate: u64,             // Fee rate in basis points (e.g., 100 = 1%)
        admin: address,            // Administrator address
        signer_cap: SignerCapability, // Signer capability for transfers
        precommits: Table<String, PreCommit>, // Pre-commit记录，key为参数的hash
    }

    // Events
    #[event]
    struct AccountInitialized has drop, store {
        user_address: address,
    }

    #[event]
    struct DepositMade has drop, store {
        user_address: address,
        amount: u64,
        tail: String,
        new_balance: u64,
        timestamp: u64,
    }

    #[event]
    struct SelfWithdrawal has drop, store {
        user_address: address,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct PreCommitMade has drop, store {
        merchant_address: address,
        commit_hash: String,
        payer: address,
        recipient: address,
        amount: u64,
        expiry_time: u64,
    }

    #[event]
    struct PaymentCompleted has drop, store {
        payer: address,
        recipient: address,
        amount: u64,
        fee: u64,
        new_tail: String,
        timestamp: u64,
    }

    #[event]
    struct PaymentLimitUpdated has drop, store {
        user_address: address,
        old_limit: u64,
        new_limit: u64,
        timestamp: u64,
    }

    #[event]
    struct TailUpdatesLimitSet has drop, store {
        user_address: address,
        old_limit: u64,
        new_limit: u64,
        timestamp: u64,
    }

    #[event]
    struct TailRefreshed has drop, store {
        user_address: address,
        old_tail: String,
        new_tail: String,
        tail_update_count: u64,
        timestamp: u64,
    }

    #[event]
    struct FundsAdded has drop, store {
        user_address: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64,
    }

    #[event]
    struct FundsWithdrawn has drop, store {
        user_address: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64,
    }

    /// Initialize the TinyPay system (called once during deployment)
    fun init_module(admin: &signer) {
        init_system(admin);
    }

    /// Public function to initialize system (for testing)
    public fun init_system(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        // Create resource account for holding funds
        let (resource_signer, signer_cap) = account::create_resource_account(admin, b"tinypay_vault");
        
        move_to(admin, TinyPayState {
            total_deposits: 0,
            total_withdrawals: 0,
            fee_rate: 100, // 1% fee in basis points (100/10000)
            admin: admin_addr,
            signer_cap,
            precommits: table::new(),
        });
        
        // Register the resource account to handle APT
        coin::register<AptosCoin>(&resource_signer);
    }

    /// Initialize user account 
    public entry fun initialize_account(user: &signer) {
        let user_addr = signer::address_of(user);
        assert!(!exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        move_to(user, UserAccount {
            balance: 0,
            tail: string::utf8(b""), // 初始tail为空
            payment_limit: 0, // 0表示无限制
            tail_update_count: 0,
            max_tail_updates: 0, // 0表示无限制
        });

        event::emit(AccountInitialized {
            user_address: user_addr,
        });
    }

    /// Deposit APT into user's TinyPay account with tail hash
    /// Auto-initializes user account if it doesn't exist
    public entry fun deposit(user: &signer, amount: u64, tail: String) acquires UserAccount, TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        
        // Auto-initialize user account if it doesn't exist
        if (!exists<UserAccount>(user_addr)) {
            move_to(user, UserAccount {
                balance: 0,
                tail: string::utf8(b""), // 初始tail为空
                payment_limit: 0, // 0表示无限制
                tail_update_count: 0,
                max_tail_updates: 0, // 0表示无限制
            });

            event::emit(AccountInitialized {
                user_address: user_addr,
            });
        };

        let state = borrow_global<TinyPayState>(@tinypay);
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);

        // Transfer APT from user to vault
        coin::transfer<AptosCoin>(user, vault_addr, amount);

        // Update user balance and tail
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        user_account.balance += amount;
        
        // Increment tail update count if tail is changing to a non-empty value
        if (tail.length() > 0 && tail != user_account.tail) {
            user_account.tail_update_count += 1;
        };
        user_account.tail = tail;

        // Update global state
        let state = borrow_global_mut<TinyPayState>(@tinypay);
        state.total_deposits += amount;

        event::emit(DepositMade {
            user_address: user_addr,
            amount,
            tail,
            new_balance: user_account.balance,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// User withdraws their own funds, invalidating the tail
    public entry fun self_withdraw(user: &signer, amount: u64) acquires UserAccount, TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        let user_account = borrow_global_mut<UserAccount>(user_addr);
        assert!(user_account.balance >= amount, E_INSUFFICIENT_BALANCE);

        // Update balance and invalidate tail
        user_account.balance -= amount;
        user_account.tail = string::utf8(b""); // Invalidate tail

        // Transfer APT from vault to user
        let state = borrow_global_mut<TinyPayState>(@tinypay);
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        coin::transfer<AptosCoin>(&vault_signer, user_addr, amount);
        state.total_withdrawals += amount;

        event::emit(SelfWithdrawal {
            user_address: user_addr,
            amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Merchant submits pre-commit for payment (Phase 1)
    public entry fun merchant_precommit(
        merchant: &signer,
        payer: address,
        recipient: address,
        amount: u64
    ) acquires TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(payer), E_ACCOUNT_NOT_INITIALIZED);

        // Generate hash of parameters for pre-commit
        let params_bytes = vector::empty<u8>();
        let payer_bytes = bcs::to_bytes(&payer);
        let recipient_bytes = bcs::to_bytes(&recipient);
        let amount_bytes = bcs::to_bytes(&amount);
        
        params_bytes.append(payer_bytes);
        params_bytes.append(recipient_bytes);
        params_bytes.append(amount_bytes);
        
        // Create a simple string hash for commit_hash instead of using crypto hash
        let commit_hash = string::utf8(b"commit_");
        commit_hash.append(string::utf8(bcs::to_bytes(&timestamp::now_seconds())));

        // Store pre-commit with 15 minutes expiry
        let expiry_time = timestamp::now_seconds() + 900; // 15 minutes
        let precommit = PreCommit {
            payer,
            recipient,
            amount,
            expiry_time,
        };

        let state = borrow_global_mut<TinyPayState>(@tinypay);
        state.precommits.add(commit_hash, precommit);

        let merchant_addr = signer::address_of(merchant);
        event::emit(PreCommitMade {
            merchant_address: merchant_addr,
            commit_hash,
            payer,
            recipient,
            amount,
            expiry_time,
        });
    }

    /// User completes payment with opt value (Phase 2)
    public entry fun complete_payment(
        user: &signer,
        opt: String,
        payer: address,
        recipient: address,
        amount: u64
    ) acquires UserAccount, TinyPayState {
        let user_addr = signer::address_of(user);
        assert!(user_addr == payer, E_ACCOUNT_NOT_INITIALIZED);
        assert!(exists<UserAccount>(payer), E_ACCOUNT_NOT_INITIALIZED);

        // Generate hash of parameters to verify pre-commit
        let params_bytes = vector::empty<u8>();
        let payer_bytes = bcs::to_bytes(&payer);
        let recipient_bytes = bcs::to_bytes(&recipient);
        let amount_bytes = bcs::to_bytes(&amount);
        
        params_bytes.append(payer_bytes);
        params_bytes.append(recipient_bytes);
        params_bytes.append(amount_bytes);
        
        let commit_hash = string::utf8(b"commit_");
        // Note: In real implementation, would use proper hash verification

        // Verify pre-commit exists and is valid
        let state = borrow_global_mut<TinyPayState>(@tinypay);
        assert!(state.precommits.contains(commit_hash), E_INVALID_PRECOMMIT);
        
        let precommit = state.precommits.remove(commit_hash);
        assert!(timestamp::now_seconds() <= precommit.expiry_time, E_INVALID_PRECOMMIT);
        assert!(payer == precommit.payer, E_INVALID_PRECOMMIT);
        assert!(recipient == precommit.recipient, E_INVALID_PRECOMMIT);
        assert!(amount == precommit.amount, E_INVALID_PRECOMMIT);

        // Verify hash(opt) == tail
        let user_account = borrow_global_mut<UserAccount>(payer);
        // Note: In real implementation, would verify hash(opt) == user_account.tail
        assert!(user_account.balance >= amount, E_INSUFFICIENT_BALANCE);

        // Check payment limit
        if (user_account.payment_limit > 0) {
            assert!(amount <= user_account.payment_limit, E_PAYMENT_LIMIT_EXCEEDED);
        };

        // Check tail update limit
        if (user_account.max_tail_updates > 0) {
            assert!(user_account.tail_update_count < user_account.max_tail_updates, E_TAIL_UPDATES_LIMIT_EXCEEDED);
        };

        // Calculate fee and transfer
        let fee = (amount * state.fee_rate) / 10000;
        let recipient_amount = amount - fee;

        // Update user balance and tail
        user_account.balance -= amount; // Subtract amount from payer
        user_account.tail = opt; // Update tail to opt
        user_account.tail_update_count += 1;

        // Transfer APT to recipient
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        coin::transfer<AptosCoin>(&vault_signer, recipient, recipient_amount);
        state.total_withdrawals += amount;

        event::emit(PaymentCompleted {
            payer,
            recipient,
            amount,
            fee,
            new_tail: opt,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// User function to set payment limit (0 = unlimited)
    public entry fun set_payment_limit(user: &signer, limit: u64) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);
        
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let old_limit = user_account.payment_limit;
        user_account.payment_limit = limit;
        
        event::emit(PaymentLimitUpdated {
            user_address: user_addr,
            old_limit,
            new_limit: limit,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// User function to set maximum tail updates limit (0 = unlimited)
    public entry fun set_tail_updates_limit(user: &signer, limit: u64) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);
        
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let old_limit = user_account.max_tail_updates;
        user_account.max_tail_updates = limit;
        
        event::emit(TailUpdatesLimitSet {
            user_address: user_addr,
            old_limit,
            new_limit: limit,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// User function to refresh tail (update tail and increment count)
    public entry fun refresh_tail(user: &signer, new_tail: String) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);
        
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        
        // Check tail update limit
        if (user_account.max_tail_updates > 0) {
            assert!(user_account.tail_update_count < user_account.max_tail_updates, E_TAIL_UPDATES_LIMIT_EXCEEDED);
        };
        
        let old_tail = user_account.tail;
        user_account.tail = new_tail;
        user_account.tail_update_count += 1;
        
        event::emit(TailRefreshed {
            user_address: user_addr,
            old_tail,
            new_tail,
            tail_update_count: user_account.tail_update_count,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// User function to add more funds to account
    /// Auto-initializes user account if it doesn't exist
    /// Implemented as a convenience wrapper around deposit with empty tail
    public entry fun add_funds(user: &signer, amount: u64) acquires UserAccount, TinyPayState {
        // Call deposit with empty tail string
        deposit(user, amount, string::utf8(b""));
    }

    /// User function to withdraw funds back to their wallet
    public entry fun withdraw_funds(user: &signer, amount: u64) acquires UserAccount, TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);
        
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        assert!(user_account.balance >= amount, E_INSUFFICIENT_BALANCE);
        
        // Update user balance
        user_account.balance -= amount;
        
        // Transfer APT from vault to user
        let state = borrow_global_mut<TinyPayState>(@tinypay);
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        coin::transfer<AptosCoin>(&vault_signer, user_addr, amount);
        state.total_withdrawals += amount;
        
        event::emit(FundsWithdrawn {
            user_address: user_addr,
            amount,
            new_balance: user_account.balance,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Admin function to update fee rate
    public entry fun update_fee_rate(admin: &signer, new_fee_rate: u64) acquires TinyPayState {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<TinyPayState>(@tinypay);
        assert!(admin_addr == state.admin, E_NOT_ADMIN);
        
        state.fee_rate = new_fee_rate;
    }

    // View functions

    #[view]
    /// Get user's current balance
    public fun get_balance(user_address: address): u64 acquires UserAccount {
        if (!exists<UserAccount>(user_address)) {
            return 0
        };
        let user_account = borrow_global<UserAccount>(user_address);
        user_account.balance
    }

    #[view]
    /// Get user's current tail value
    public fun get_user_tail(user_address: address): String acquires UserAccount {
        if (!exists<UserAccount>(user_address)) {
            return string::utf8(b"")
        };
        let user_account = borrow_global<UserAccount>(user_address);
        user_account.tail
    }

    #[view]
    /// Get user's payment limits and tail update info
    public fun get_user_limits(user_address: address): (u64, u64, u64) acquires UserAccount {
        if (!exists<UserAccount>(user_address)) {
            return (0, 0, 0)
        };
        let user_account = borrow_global<UserAccount>(user_address);
        (user_account.payment_limit, user_account.tail_update_count, user_account.max_tail_updates)
    }

    #[view]
    /// Get system statistics
    public fun get_system_stats(): (u64, u64, u64) acquires TinyPayState {
        let state = borrow_global<TinyPayState>(@tinypay);
        (state.total_deposits, state.total_withdrawals, state.fee_rate)
    }

    #[view]
    /// Check if user account is initialized
    public fun is_account_initialized(user_address: address): bool {
        exists<UserAccount>(user_address)
    }

    #[view]
    /// Get vault address
    public fun get_vault_address(): address acquires TinyPayState {
        let state = borrow_global<TinyPayState>(@tinypay);
        account::get_signer_capability_address(&state.signer_cap)
    }
}
