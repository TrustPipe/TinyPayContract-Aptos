/// TinyPay FA - Modern Offline Payment System for Aptos using Fungible Asset Standard
/// Supports multiple FA tokens (APT, USDC, USDT, etc.) for offline payment vouchers
/// Allows users to deposit FA tokens, generate offline payment vouchers,
/// and enables merchants to redeem those vouchers for token withdrawals.
module tinypay::tinypay_fa {
    use std::bcs;
    use std::hash;
    use std::signer;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

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
    /// Fungible asset is not supported
    const E_ASSET_NOT_SUPPORTED: u64 = 10;
    /// Fungible asset is already supported
    const E_ASSET_ALREADY_SUPPORTED: u64 = 11;

    /// User account information storing balances for multiple FA tokens and tail
    struct UserAccount has key {
        balances: Table<address, u64>,
        // Balances for different FA tokens (keyed by metadata object address)
        tail: vector<u8>,
        // Current tail hash value (SHA256 bytes)
        payment_limit: u64,
        // Maximum payment amount per transaction (0 = unlimited)
        tail_update_count: u64,
        // Number of times tail has been updated
        max_tail_updates: u64 // Maximum allowed tail updates (0 = unlimited)
    }

    /// Pre-commit information for merchant payments
    struct PreCommit has store, drop {
        merchant: address,
        expiry_time: u64
    }


    /// Global state for the TinyPay FA system
    struct TinyPayState has key {
        total_deposits: Table<address, u64>,
        // Total deposits per FA type (keyed by metadata address)
        total_withdrawals: Table<address, u64>,
        // Total withdrawals per FA type
        fee_rate: u64,
        // Fee rate in basis points (e.g., 100 = 1%)
        admin: address,
        paymaster: address,
        signer_cap: SignerCapability,
        precommits: Table<vector<u8>, PreCommit>,
        supported_assets: Table<address, bool> // Track supported FA types (keyed by metadata address)
    }

    // Events
    #[event]
    struct AccountInitialized has drop, store {
        user_address: address
    }

    #[event]
    struct DepositMade has drop, store {
        user_address: address,
        asset_metadata: address,
        amount: u64,
        tail: vector<u8>,
        new_balance: u64,
        timestamp: u64
    }

    #[event]
    struct PaymentCompleted has drop, store {
        payer: address,
        recipient: address,
        asset_metadata: address,
        amount: u64,
        fee: u64,
        new_tail: vector<u8>,
        timestamp: u64
    }

    #[event]
    struct FundsWithdrawn has drop, store {
        user_address: address,
        asset_metadata: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64
    }

    #[event]
    struct AssetSupported has drop, store {
        asset_metadata: address,
        timestamp: u64
    }

    #[event]
    struct PreCommitMade has drop, store {
        merchant_address: address,
        commit_hash: vector<u8>,
        expiry_time: u64,
        timestamp: u64
    }

    #[event]
    struct PaymentLimitUpdated has drop, store {
        user_address: address,
        old_limit: u64,
        new_limit: u64,
        timestamp: u64
    }

    #[event]
    struct TailUpdatesLimitSet has drop, store {
        user_address: address,
        old_limit: u64,
        new_limit: u64,
        timestamp: u64
    }

    #[event]
    struct TailRefreshed has drop, store {
        user_address: address,
        old_tail: vector<u8>,
        new_tail: vector<u8>,
        tail_update_count: u64,
        timestamp: u64
    }

    /// Get the admin address where TinyPayState is stored
    fun get_admin_address(): address {
        @tinypay
    }

    /// Merchant pre-commit for payment with FA support
    public entry fun merchant_precommit(
        merchant: &signer,
        payer: address,
        recipient: address,
        amount: u64,
        asset_metadata: Object<Metadata>,
        otp: vector<u8>
    ) acquires TinyPayState {
        let merchant_addr = signer::address_of(merchant);
        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        let metadata_addr = object::object_address(&asset_metadata);

        // Check if asset is supported
        assert!(state.supported_assets.contains(metadata_addr), E_ASSET_NOT_SUPPORTED);

        // Generate commit hash from payment parameters
        let params_bytes = vector::empty<u8>();
        let payer_bytes = bcs::to_bytes(&payer);
        let recipient_bytes = bcs::to_bytes(&recipient);
        let amount_bytes = bcs::to_bytes(&amount);
        let otp_bytes = bcs::to_bytes(&otp);
        let metadata_bytes = bcs::to_bytes(&metadata_addr);

        params_bytes.append(payer_bytes);
        params_bytes.append(recipient_bytes);
        params_bytes.append(amount_bytes);
        params_bytes.append(otp_bytes);
        params_bytes.append(metadata_bytes);

        let commit_hash = hash::sha2_256(params_bytes);
        let expiry_time = timestamp::now_seconds() + 900; // 15 minutes

        // Store pre-commit
        state.precommits.add(commit_hash, PreCommit {
            merchant: merchant_addr,
            expiry_time
        });

        event::emit(PreCommitMade {
            merchant_address: merchant_addr,
            commit_hash,
            expiry_time,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Set payment limit for user account
    public entry fun set_payment_limit(
        user: &signer,
        limit: u64
    ) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let old_limit = user_account.payment_limit;
        user_account.payment_limit = limit;

        event::emit(PaymentLimitUpdated {
            user_address: user_addr,
            old_limit,
            new_limit: limit,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Set tail updates limit for user account
    public entry fun set_tail_updates_limit(
        user: &signer,
        limit: u64
    ) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let old_limit = user_account.max_tail_updates;
        user_account.max_tail_updates = limit;

        event::emit(TailUpdatesLimitSet {
            user_address: user_addr,
            old_limit,
            new_limit: limit,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Refresh tail for user account
    public entry fun refresh_tail(
        user: &signer,
        new_tail: vector<u8>
    ) acquires UserAccount {
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
            timestamp: timestamp::now_seconds()
        });
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

    /// Initialize the TinyPay FA system
    fun init_module(admin: &signer) {
        init_system(admin);
    }

    /// Public function to initialize system
    public fun init_system(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        let (_resource_signer, signer_cap) = account::create_resource_account(admin, b"tinypay_fa_vault");

        move_to(admin, TinyPayState {
            total_deposits: table::new(),
            total_withdrawals: table::new(),
            fee_rate: 100, // 1% fee
            admin: admin_addr,
            paymaster: admin_addr,
            signer_cap,
            precommits: table::new(),
            supported_assets: table::new()
        });

        // Vault is managed through primary_fungible_store, no need for additional resource
    }

    /// Admin function to add support for a new FA type
    public entry fun add_asset_support(
        admin: &signer,
        asset_metadata: Object<Metadata>
    ) acquires TinyPayState {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        assert!(admin_addr == state.admin, E_NOT_ADMIN);

        let metadata_addr = object::object_address(&asset_metadata);
        assert!(!state.supported_assets.contains(metadata_addr), E_ASSET_ALREADY_SUPPORTED);

        // Create primary store for the vault if it doesn't exist
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);
        primary_fungible_store::ensure_primary_store_exists(vault_addr, asset_metadata);

        // Update state
        state.supported_assets.add(metadata_addr, true);
        state.total_deposits.add(metadata_addr, 0);
        state.total_withdrawals.add(metadata_addr, 0);

        event::emit(AssetSupported {
            asset_metadata: metadata_addr,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Deposit FA tokens into user's TinyPay account
    public entry fun deposit(
        user: &signer,
        asset_metadata: Object<Metadata>,
        amount: u64,
        tail: vector<u8>
    ) acquires UserAccount, TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        let metadata_addr = object::object_address(&asset_metadata);

        // Check if asset is supported
        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        assert!(state.supported_assets.contains(metadata_addr), E_ASSET_NOT_SUPPORTED);

        // Auto-initialize user account if needed
        if (!exists<UserAccount>(user_addr)) {
            assert!(tail.length() > 0, E_INVALID_TAIL);
            move_to(user, UserAccount {
                balances: table::new(),
                tail: vector::empty<u8>(),
                payment_limit: 0,
                tail_update_count: 0,
                max_tail_updates: 0
            });
            event::emit(AccountInitialized { user_address: user_addr });
        };

        // Transfer FA tokens to vault
        let vault_addr = account::get_signer_capability_address(&state.signer_cap);
        primary_fungible_store::transfer(user, asset_metadata, vault_addr, amount);

        // Update user balance
        let user_account = borrow_global_mut<UserAccount>(user_addr);
        let current_balance = if (user_account.balances.contains(metadata_addr)) {
            *user_account.balances.borrow(metadata_addr)
        } else {
            user_account.balances.add(metadata_addr, 0);
            0
        };
        *user_account.balances.borrow_mut(metadata_addr) = current_balance + amount;

        // Update tail if provided
        if (tail.length() > 0 && tail != user_account.tail) {
            user_account.tail_update_count += 1;
        };
        user_account.tail = tail;

        // Update global state
        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        *state.total_deposits.borrow_mut(metadata_addr) =
            *state.total_deposits.borrow(metadata_addr) + amount;

        event::emit(DepositMade {
            user_address: user_addr,
            asset_metadata: metadata_addr,
            amount,
            tail,
            new_balance: *user_account.balances.borrow(metadata_addr),
            timestamp: timestamp::now_seconds()
        });
    }

    /// Complete payment with specified FA type
    public entry fun complete_payment(
        caller: &signer,
        otp: vector<u8>,
        payer: address,
        recipient: address,
        amount: u64,
        asset_metadata: Object<Metadata>,
        commit_hash: vector<u8>
    ) acquires UserAccount, TinyPayState {
        let caller_addr = signer::address_of(caller);
        let metadata_addr = object::object_address(&asset_metadata);

        assert!(exists<UserAccount>(payer), E_ACCOUNT_NOT_INITIALIZED);

        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        assert!(state.supported_assets.contains(metadata_addr), E_ASSET_NOT_SUPPORTED);

        let is_paymaster = caller_addr == state.paymaster;

        // Verify commit_hash if not paymaster
        if (!is_paymaster) {
            let params_bytes = vector::empty<u8>();
            let payer_bytes = bcs::to_bytes(&payer);
            let recipient_bytes = bcs::to_bytes(&recipient);
            let amount_bytes = bcs::to_bytes(&amount);
            let otp_bytes = bcs::to_bytes(&otp);
            let metadata_bytes = bcs::to_bytes(&metadata_addr);

            params_bytes.append(payer_bytes);
            params_bytes.append(recipient_bytes);
            params_bytes.append(amount_bytes);
            params_bytes.append(otp_bytes);
            params_bytes.append(metadata_bytes);

            let computed_hash = hash::sha2_256(params_bytes);
            assert!(computed_hash == commit_hash, E_INVALID_PRECOMMIT);
            assert!(state.precommits.contains(commit_hash), E_INVALID_PRECOMMIT);

            let precommit = state.precommits.remove(commit_hash);
            assert!(timestamp::now_seconds() <= precommit.expiry_time, E_INVALID_PRECOMMIT);
        };

        // Verify otp against tail
        let user_account = borrow_global_mut<UserAccount>(payer);
        let otp_hash_bytes = hash::sha2_256(otp);
        let hex_ascii_bytes = bytes_to_hex_ascii(otp_hash_bytes);
        assert!(hex_ascii_bytes == user_account.tail, E_INVALID_OPT);

        // Check balance
        assert!(user_account.balances.contains(metadata_addr), E_INSUFFICIENT_BALANCE);
        let current_balance = *user_account.balances.borrow(metadata_addr);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Check payment limit
        if (user_account.payment_limit > 0) {
            assert!(amount <= user_account.payment_limit, E_PAYMENT_LIMIT_EXCEEDED);
        };

        // Calculate fee and transfer
        let fee = (amount * state.fee_rate) / 10000;
        let recipient_amount = amount - fee;

        // Update user balance and tail
        *user_account.balances.borrow_mut(metadata_addr) = current_balance - amount;
        user_account.tail = otp;
        user_account.tail_update_count += 1;

        // Transfer FA tokens to recipient from vault
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        primary_fungible_store::transfer(&vault_signer, asset_metadata, recipient, recipient_amount);

        *state.total_withdrawals.borrow_mut(metadata_addr) =
            *state.total_withdrawals.borrow(metadata_addr) + amount;

        event::emit(PaymentCompleted {
            payer,
            recipient,
            asset_metadata: metadata_addr,
            amount,
            fee,
            new_tail: otp,
            timestamp: timestamp::now_seconds()
        });
    }

    /// Withdraw funds back to user's wallet
    public entry fun withdraw_funds(
        user: &signer,
        asset_metadata: Object<Metadata>,
        amount: u64
    ) acquires UserAccount, TinyPayState {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        let metadata_addr = object::object_address(&asset_metadata);

        assert!(exists<UserAccount>(user_addr), E_ACCOUNT_NOT_INITIALIZED);

        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        assert!(state.supported_assets.contains(metadata_addr), E_ASSET_NOT_SUPPORTED);

        let user_account = borrow_global_mut<UserAccount>(user_addr);
        assert!(user_account.balances.contains(metadata_addr), E_INSUFFICIENT_BALANCE);

        let current_balance = *user_account.balances.borrow(metadata_addr);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);

        // Update balance
        *user_account.balances.borrow_mut(metadata_addr) = current_balance - amount;

        // Transfer FA tokens from vault to user
        let vault_signer = account::create_signer_with_capability(&state.signer_cap);
        primary_fungible_store::transfer(&vault_signer, asset_metadata, user_addr, amount);

        let admin_addr = get_admin_address();
        let state = borrow_global_mut<TinyPayState>(admin_addr);
        *state.total_withdrawals.borrow_mut(metadata_addr) =
            *state.total_withdrawals.borrow(metadata_addr) + amount;

        event::emit(FundsWithdrawn {
            user_address: user_addr,
            asset_metadata: metadata_addr,
            amount,
            new_balance: *user_account.balances.borrow(metadata_addr),
            timestamp: timestamp::now_seconds()
        });
    }

    // View functions
    #[view]
    public fun get_balance(user_address: address, asset_metadata: Object<Metadata>): u64 acquires UserAccount {
        if (!exists<UserAccount>(user_address)) return 0;

        let user_account = borrow_global<UserAccount>(user_address);
        let metadata_addr = object::object_address(&asset_metadata);

        if (user_account.balances.contains(metadata_addr)) {
            *user_account.balances.borrow(metadata_addr)
        } else {
            0
        }
    }

    #[view]
    public fun is_asset_supported(asset_metadata: Object<Metadata>): bool acquires TinyPayState {
        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        let metadata_addr = object::object_address(&asset_metadata);
        state.supported_assets.contains(metadata_addr)
    }

    #[view]
    public fun get_user_limits(user_address: address): (u64, u64, u64) acquires UserAccount {
        if (!exists<UserAccount>(user_address)) {
            return (0, 0, 0)
        };

        let user_account = borrow_global<UserAccount>(user_address);
        (user_account.payment_limit, user_account.tail_update_count, user_account.max_tail_updates)
    }

    #[view]
    public fun get_user_tail(user_address: address): vector<u8> acquires UserAccount {
        if (!exists<UserAccount>(user_address)) {
            return vector::empty<u8>()
        };

        let user_account = borrow_global<UserAccount>(user_address);
        user_account.tail
    }

    #[view]
    public fun get_system_stats(asset_metadata: Object<Metadata>): (u64, u64, u64) acquires TinyPayState {
        let admin_addr = get_admin_address();
        let state = borrow_global<TinyPayState>(admin_addr);
        let metadata_addr = object::object_address(&asset_metadata);

        let total_deposits = if (state.total_deposits.contains(metadata_addr)) {
            *state.total_deposits.borrow(metadata_addr)
        } else {
            0
        };
        let total_withdrawals = if (state.total_withdrawals.contains(metadata_addr)) {
            *state.total_withdrawals.borrow(metadata_addr)
        } else {
            0
        };

        (total_deposits, total_withdrawals, state.fee_rate)
    }
}
