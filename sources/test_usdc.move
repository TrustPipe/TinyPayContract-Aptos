/// Test USDC Token for TinyPay Testing
/// This is a simple test token implementation for testing purposes only
/// DO NOT use in production environments
module tinypay::test_usdc {
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::event;

    /// Error codes
    /// Only admin can perform this operation
    const E_NOT_ADMIN: u64 = 1;
    /// Insufficient balance for the requested operation
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    /// Invalid amount provided (must be greater than 0)
    const E_INVALID_AMOUNT: u64 = 3;

    /// Test USDC coin type
    struct TestUSDC has key {}

    /// Capabilities for managing the test USDC token
    struct TestUSDCCapabilities has key {
        mint_cap: MintCapability<TestUSDC>,
        burn_cap: BurnCapability<TestUSDC>,
        freeze_cap: FreezeCapability<TestUSDC>,
        admin: address,
    }

    // Events
    #[event]
    struct TokenMinted has drop, store {
        recipient: address,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct TokenBurned has drop, store {
        account: address,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct AdminTransferred has drop, store {
        old_admin: address,
        new_admin: address,
        timestamp: u64
    }

    /// Initialize the test USDC token
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        // Initialize the coin with metadata
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<TestUSDC>(
            admin,
            string::utf8(b"Test USD Coin"),
            string::utf8(b"USDC"),
            6, // 6 decimal places like real USDC
            true, // monitor_supply
        );

        // Store capabilities
        move_to(admin, TestUSDCCapabilities {
            mint_cap,
            burn_cap,
            freeze_cap,
            admin: admin_addr,
        });

        // Register the admin for the coin
        coin::register<TestUSDC>(admin);
    }

    /// Public function to initialize the test USDC (for manual initialization)
    public fun initialize_test_usdc(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        // Initialize the coin with metadata
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<TestUSDC>(
            admin,
            string::utf8(b"Test USD Coin"),
            string::utf8(b"USDC"),
            6, // 6 decimal places like real USDC
            true, // monitor_supply
        );

        // Store capabilities
        move_to(admin, TestUSDCCapabilities {
            mint_cap,
            burn_cap,
            freeze_cap,
            admin: admin_addr,
        });

        // Register the admin for the coin
        coin::register<TestUSDC>(admin);
    }

    /// Mint test USDC tokens to a recipient
    public entry fun mint(
        admin: &signer,
        recipient: address,
        amount: u64
    ) acquires TestUSDCCapabilities {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<TestUSDCCapabilities>(admin_addr);
        assert!(admin_addr == caps.admin, E_NOT_ADMIN);

        // Register recipient if not already registered
        if (!coin::is_account_registered<TestUSDC>(recipient)) {
            coin::register<TestUSDC>(admin);
        };

        // Mint and deposit coins
        let coins = coin::mint<TestUSDC>(amount, &caps.mint_cap);
        coin::deposit<TestUSDC>(recipient, coins);

        event::emit(TokenMinted {
            recipient,
            amount,
            timestamp: aptos_framework::timestamp::now_seconds()
        });
    }

    /// Mint test USDC tokens to the admin's account
    public entry fun mint_to_admin(
        admin: &signer,
        amount: u64
    ) acquires TestUSDCCapabilities {
        let admin_addr = signer::address_of(admin);
        mint(admin, admin_addr, amount);
    }

    /// Burn test USDC tokens from an account
    public entry fun burn(
        account: &signer,
        amount: u64
    ) acquires TestUSDCCapabilities {
        assert!(amount > 0, E_INVALID_AMOUNT);

        let account_addr = signer::address_of(account);
        assert!(coin::balance<TestUSDC>(account_addr) >= amount, E_INSUFFICIENT_BALANCE);

        // Get admin address to access capabilities
        let caps = borrow_global<TestUSDCCapabilities>(@tinypay);

        // Withdraw and burn coins
        let coins = coin::withdraw<TestUSDC>(account, amount);
        coin::burn<TestUSDC>(coins, &caps.burn_cap);

        event::emit(TokenBurned {
            account: account_addr,
            amount,
            timestamp: aptos_framework::timestamp::now_seconds()
        });
    }

    /// Transfer admin rights to a new address
    public entry fun transfer_admin(
        current_admin: &signer,
        new_admin: address
    ) acquires TestUSDCCapabilities {
        let current_admin_addr = signer::address_of(current_admin);
        let caps = borrow_global_mut<TestUSDCCapabilities>(current_admin_addr);
        assert!(current_admin_addr == caps.admin, E_NOT_ADMIN);

        let old_admin = caps.admin;
        caps.admin = new_admin;

        event::emit(AdminTransferred {
            old_admin,
            new_admin,
            timestamp: aptos_framework::timestamp::now_seconds()
        });
    }

    /// Register an account to receive test USDC
    public entry fun register(account: &signer) {
        coin::register<TestUSDC>(account);
    }

    /// Batch mint to multiple recipients (useful for testing)
    public entry fun batch_mint(
        admin: &signer,
        recipients: vector<address>,
        amounts: vector<u64>
    ) acquires TestUSDCCapabilities {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<TestUSDCCapabilities>(admin_addr);
        assert!(admin_addr == caps.admin, E_NOT_ADMIN);

        let len = recipients.length();
        assert!(len == amounts.length(), E_INVALID_AMOUNT);

        let i = 0;
        while (i < len) {
            let recipient = recipients[i];
            let amount = amounts[i];

            if (amount > 0) {
                // Register recipient if not already registered
                if (!coin::is_account_registered<TestUSDC>(recipient)) {
                    // We can't register for other accounts, so skip if not registered
                    i += 1;
                    continue
                };

                // Mint and deposit coins
                let coins = coin::mint<TestUSDC>(amount, &caps.mint_cap);
                coin::deposit<TestUSDC>(recipient, coins);

                event::emit(TokenMinted {
                    recipient,
                    amount,
                    timestamp: aptos_framework::timestamp::now_seconds()
                });
            };

            i += 1;
        };
    }

    // View functions
    #[view]
    public fun get_balance(account: address): u64 {
        coin::balance<TestUSDC>(account)
    }

    #[view]
    public fun get_total_supply(): option::Option<u128> {
        coin::supply<TestUSDC>()
    }

    #[view]
    public fun get_coin_info(): (String, String, u8) {
        (
            coin::name<TestUSDC>(),
            coin::symbol<TestUSDC>(),
            coin::decimals<TestUSDC>()
        )
    }

    #[view]
    public fun is_registered(account: address): bool {
        coin::is_account_registered<TestUSDC>(account)
    }

    #[view]
    public fun get_admin(): address acquires TestUSDCCapabilities {
        let caps = borrow_global<TestUSDCCapabilities>(@tinypay);
        caps.admin
    }

    // Test helper functions
    #[test_only]
    public fun init_for_test(admin: &signer) {
        initialize_test_usdc(admin);
    }

    #[test_only]
    public fun mint_for_test(admin: &signer, recipient: address, amount: u64) acquires TestUSDCCapabilities {
        mint(admin, recipient, amount);
    }
}
