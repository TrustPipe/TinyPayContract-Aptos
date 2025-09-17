/// TinyPay Multi-Coin - Offline Payment System for Aptos supporting multiple coins
/// Allows users to deposit various coins (APT, USDT, USDC, etc.), generate offline payment vouchers,
/// and enables merchants to redeem those vouchers for coin withdrawals.
module tinypay::tinypay {
    use std::signer;
    use std::type_info::{Self, TypeInfo};
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use std::bcs;
    use std::vector;
    use std::hash;
    use std::string::String;

    // Error codes
    /// Insufficient balance for the requested operation
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    /// Invalid amount provided (must be greater than 0)
    const E_INVALID_AMOUNT: u64 = 2;
    /// User account has not been initialized
    const E_ACCOUNT_NOT_INITIALIZED: u64 = 3;
    /// Invalid tail value provided
    const E_INVALID_TAIL: u64 = 4;
    /// Invalid operation type provided
    const E_INVALID_OPT: u64 = 5;
    /// Invalid precommit value provided
    const E_INVALID_PRECOMMIT: u64 = 6;
    /// Only admin can perform this operation
    const E_NOT_ADMIN: u64 = 7;
    /// Payment amount exceeds the configured limit
    const E_PAYMENT_LIMIT_EXCEEDED: u64 = 8;
    /// Tail update limit has been exceeded
    const E_TAIL_UPDATES_LIMIT_EXCEEDED: u64 = 9;
    /// Coin type is not supported
    const E_COIN_NOT_SUPPORTED: u64 = 10;
    /// Coin type is already supported
    const E_COIN_ALREADY_SUPPORTED: u64 = 11;

    /// User account information storing balances for multiple coins and tail
    struct UserAccount has key {
        balances: Table<TypeInfo, u64>, // Balances for different coin types
        tail: vector<u8>, // Current tail hash value (SHA256 bytes)
        payment_limit: u64, // Maximum payment amount per transaction (0 = unlimited)
        tail_update_count: u64, // Number of times tail has been updated
        max_tail_updates: u64 // Maximum allowed tail updates (0 = unlimited)
    }

    /// Pre-commit information for merchant payments
    struct PreCommit has store, drop {
        merchant: address,
        expiry_time: u64
    }

    /// Coin vault for storing a specific coin type
    struct CoinVault<phantom CoinType> has key {
        coins: Coin<CoinType>
    }

    /// Global state for the TinyPay system
    struct TinyPayState has key {
        total_deposits: Table<TypeInfo, u64>, // Total deposits per coin type
        total_withdrawals: Table<TypeInfo, u64>, // Total withdrawals per coin type
        fee_rate: u64, // Fee rate in basis points (e.g., 100 = 1%)
        admin: address,
        paymaster: address,
        signer_cap: SignerCapability,
        precommits: Table<vector<u8>, PreCommit>,
        supported_coins: Table<TypeInfo, bool> // Track supported coin types
    }

    // Events
    #[event]
    struct AccountInitialized has drop, store {
        user_address: address
    }

    #[event]
    struct DepositMade has drop, store {
        user_address: address,
        coin_type: String,
        amount: u64,
        tail: vector<u8>,
        new_balance: u64,
        timestamp: u64
    }

    #[event]
    struct PaymentCompleted has drop, store {
        payer: address,
        recipient: address,
        coin_type: String,
        amount: u64,
        fee: u64,
        new_tail: vector<u8>,
        timestamp: u64
    }

    #[event]
    struct FundsWithdrawn has drop, store {
        user_address: address,
        coin_type: String,
        amount: u64,
        new_balance: u64,
        timestamp: u64
    }

    #[event]
    struct CoinSupported has drop, store {
        coin_type: String,
        timestamp: u64
    }

    /// Get the admin address where TinyPayState is stored
    fun get_admin_address(): address {
        // We know the admin address is the module deployer address
        @0xe1b242cd787c63cd9fac2bb1ef88e6800b427e8ad65c9cf83460d4a74a94d8c5
    }

    /// Convert bytes to hex string ASCII bytes
    public fun bytes_to_hex_ascii(bytes: vector<u8>): vector<u8> {
        let hex_chars = b"0123456789abcdef";
        let result = vector::empty<u8>();
        let i = 0;
        while (i < bytes.length()) {
            let byte = bytes[i];
            let high = (byte / 16) as u64;
            let low = (byte % 16) as u64;
            result.push_back(hex_chars[high]);
            result.push_back(hex_chars[low]);
            i += 1;
        };
        result
    }

    /// Initialize the TinyPay system
    fun init_module(admin: &signer) acquires TinyPayState {
        init_system(admin);
    }

    /// Public function to initialize system
    public fun init_system(admin: &signer) acquires TinyPayState {
        let admin_addr = signer::address_of(admin);
        let (resource_signer, signer_cap) = account::create_resource_account(admin, b"tinypay_multicoin_vault");

        move_to(admin, TinyPayState {
            total_deposits: table::new(),
            total_withdrawals: table::new(),
            fee_rate: 100, // 1% fee
            admin: admin_addr,
            paymaster: admin_addr,
            signer_cap,
            precommits: table::new(),
            supported_coins: table::new()
        });

        // Add APT support after creating the state
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        let apt_type = type_info::type_of<AptosCoin>();
        state.supported_coins.add(apt_type, true);
        state.total_deposits.add(apt_type, 0);
        state.total_withdrawals.add(apt_type, 0);

        // Register and support APT by default
        coin::register<AptosCoin>(&resource_signer);
        move_to(&resource_signer, CoinVault<AptosCoin> { coins: coin::zero<AptosCoin>() });

        event::emit(CoinSupported {
            coin_type: type_info::type_name<AptosCoin>(),
            timestamp: timestamp::now_seconds()
        });
    }

    /// Admin function to add support for a new coin type
    public entry fun add_coin_support<CoinType>(admin: &signer) acquires TinyPayState {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        assert!(admin_addr == state.admin, E_NOT_ADMIN);

        let coin_type = type_info::type_of<CoinType>();
        assert!(!state.supported_coins.contains(coin_type), E_COIN_ALREADY_SUPPORTED);

        // Register coin and create vault
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        coin::register<CoinType>(&vault_signer);
        move_to(&vault_signer, CoinVault<CoinType> { coins: coin::zero<CoinType>() });

        // Update state
        state.supported_coins.add(coin_type, true);
        state.total_deposits.add(coin_type, 0);
        state.total_withdrawals.add(coin_type, 0);

        event::emit(CoinSupported {
            coin_type: type_info::type_name<CoinType>(),
            timestamp: timestamp::now_seconds()
        });
    }

    /// Deposit coins into user's TinyPay account
    public entry fun deposit<CoinType>(
        user: &signer, amount: u64, tail: vector<u8>
    ) acquires UserAccount, TinyPayState, CoinVault {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        let coin_type = type_info::type_of<CoinType>();

        // Check if coin is supported
        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        assert!(state.supported_coins.contains(coin_type), E_COIN_NOT_SUPPORTED);

        // Auto-initialize user account if needed
        if (!exists<UserAccount>(user_addr)) {
            move_to(user, UserAccount {
                balances: table::new(),
                tail: vector::empty<u8>(),
                payment_limit: 0,
                tail_update_count: 0,
                max_tail_updates: 0
            });
            event::emit(AccountInitialized { user_address: user_addr });
        };

        // Transfer coins to vault
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);
        let coins = coin::withdraw<CoinType>(user, amount);
        let vault = borrow_global_mut<CoinVault<CoinType>>(vault_addr);
        coin::merge(&mut vault.coins, coins);

        // Update user balance
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let current_balance = if (user_account.balances.contains(coin_type)) {
            *user_account.balances.borrow(coin_type)
        } else {
            user_account.balances.add(coin_type, 0);
            0
        };
        *user_account.balances.borrow_mut(coin_type) = current_balance + amount;

        // Update tail if provided
        if (tail.length() > 0 && tail != user_account.tail) {
            user_account.tail_update_count += 1;
        };
        user_account.tail = tail;

        // Update global state
        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        *state.total_deposits.borrow_mut(coin_type) = *state.total_deposits.borrow(coin_type) + amount;

        event::emit(DepositMade {
            user_address: user_addr,
            coin_type: type_info::type_name<CoinType>(),
            amount,
            tail,
            new_balance: *user_account.balances.borrow(coin_type),
            timestamp: timestamp::now_seconds()
        });
    }

    /// Complete payment with specified coin type
    public entry fun complete_payment<CoinType>(
        caller: &signer,
        opt: vector<u8>,
        payer: address,
        recipient: address,
        amount: u64,
        commit_hash: vector<u8>
    ) acquires UserAccount, TinyPayState, CoinVault {
        let caller_addr = signer::address_of(caller);
        let coin_type = type_info::type_of<CoinType>();

        assert!(exists<UserAccount>(payer), E_ACCOUNT_NOT_INITIALIZED);

        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        assert!(state.supported_coins.contains(coin_type), E_COIN_NOT_SUPPORTED);

        let is_paymaster = caller_addr == state.paymaster;

        // Verify commit_hash if not paymaster
        if (!is_paymaster) {
            let params_bytes = vector::empty<u8>();
            params_bytes.append(bcs::to_bytes(&payer));
            params_bytes.append(bcs::to_bytes(&recipient));
            params_bytes.append(bcs::to_bytes(&amount));
            params_bytes.append(bcs::to_bytes(&opt));
            params_bytes.append(bcs::to_bytes(&coin_type));

            let computed_hash = hash::sha2_256(params_bytes);
            assert!(computed_hash == commit_hash, E_INVALID_PRECOMMIT);
            assert!(state.precommits.contains(commit_hash), E_INVALID_PRECOMMIT);

            let precommit = state.precommits.remove(commit_hash);
            assert!(timestamp::now_seconds() <= precommit.expiry_time, E_INVALID_PRECOMMIT);
        };

        // Verify opt against tail
        let user_account = borrow_global_mut<UserAccount>(payer);
        let opt_hash_bytes = hash::sha2_256(opt);
        let hex_ascii_bytes = bytes_to_hex_ascii(opt_hash_bytes);
        assert!(hex_ascii_bytes == user_account.tail, E_INVALID_OPT);

        // Check balance
        assert!(user_account.balances.contains(coin_type), E_INSUFFICIENT_BALANCE);
        let current_balance = *user_account.balances.borrow(coin_type);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Check payment limit
        if (user_account.payment_limit > 0) {
            assert!(amount <= user_account.payment_limit, E_PAYMENT_LIMIT_EXCEEDED);
        };

        // Calculate fee and transfer
        let fee = (amount * state.fee_rate) / 10000;
        let recipient_amount = amount - fee;

        // Update user balance and tail
        *user_account.balances.borrow_mut(coin_type) = current_balance - amount;
        user_account.tail = opt;
        user_account.tail_update_count += 1;

        // Transfer coins to recipient
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);
        let vault = borrow_global_mut<CoinVault<CoinType>>(vault_addr);
        let payment_coins = coin::extract(&mut vault.coins, recipient_amount);
        coin::deposit(recipient, payment_coins);

        *state.total_withdrawals.borrow_mut(coin_type) = *state.total_withdrawals.borrow(coin_type) + amount;

        event::emit(PaymentCompleted {
            payer,
            recipient,
            coin_type: type_info::type_name<CoinType>(),
            amount,
            fee,
            new_tail: opt,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Withdraw funds back to user's wallet
    public entry fun withdraw_funds<CoinType>(
        user: &signer, amount: u64
    ) acquires UserAccount, TinyPayState, CoinVault {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        let coin_type = type_info::type_of<CoinType>();

        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        assert!(state.supported_coins.contains(coin_type), E_COIN_NOT_SUPPORTED);

        let user_account = borrow_global_mut<UserAccount>(user_addr);
        assert!(user_account.balances.contains(coin_type), E_INSUFFICIENT_BALANCE);

        let current_balance = *user_account.balances.borrow(coin_type);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Update balance
        *user_account.balances.borrow_mut(coin_type) = current_balance - amount;

        // Transfer coins from vault to user
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);
        let vault = borrow_global_mut<CoinVault<CoinType>>(vault_addr);
        let withdraw_coins = coin::extract(&mut vault.coins, amount);
        coin::deposit(user_addr, withdraw_coins);

        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        *state.total_withdrawals.borrow_mut(coin_type) = *state.total_withdrawals.borrow(coin_type) + amount;

        event::emit(FundsWithdrawn {
            user_address: user_addr,
            coin_type: type_info::type_name<CoinType>(),
            amount,
            new_balance: *user_account.balances.borrow(coin_type),
            timestamp: timestamp::now_seconds()
        });
    }

    // View functions
    #[view]
    public fun get_balance<CoinType>(user_address: address): u64 acquires UserAccount {
        if (!exists<UserAccount>(user_address)) return 0;

        let user_account = borrow_global<UserAccount>(user_address);
        let coin_type = type_info::type_of<CoinType>();

        if (user_account.balances.contains(coin_type)) {
            *user_account.balances.borrow(coin_type)
        } else {
            0
        }
    }

    #[view]
    public fun is_coin_supported<CoinType>(): bool acquires TinyPayState {
        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        let coin_type = type_info::type_of<CoinType>();
        state.supported_coins.contains(coin_type)
    }
}
