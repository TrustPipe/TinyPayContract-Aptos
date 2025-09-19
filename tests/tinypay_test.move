// TinyPay FA Test Suite - Comprehensive tests for FA-based offline payment system
#[test_only]
module tinypay::tinypay_test {
    use std::signer;
    use std::vector;
    use std::hash;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use tinypay::tinypay;
    use tinypay::usdc;

    // Test constants
    const INITIAL_BALANCE: u64 = 1000000; // 1M units
    const DEPOSIT_AMOUNT: u64 = 100000;   // 100K units
    const PAYMENT_AMOUNT: u64 = 50000;    // 50K units
    const WITHDRAW_AMOUNT: u64 = 25000;   // 25K units

    #[test(admin = @tinypay, user1 = @0x100, user2 = @0x200)]
    fun test_system_initialization(
        admin: &signer,
        user1: &signer,
        user2: &signer
    ) {
        // Silence unused parameter warnings
        let _ = user1;
        let _ = user2;
        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));

        // Initialize TinyPay FA system
        tinypay::init_system(admin);

        // Initialize USDC FA
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();

        // Add USDC support to TinyPay
        tinypay::add_asset_support(admin, usdc_metadata);

        // Verify asset is supported
        assert!(tinypay::is_asset_supported(usdc_metadata), 1);

        // Verify system stats
        let (total_deposits, total_withdrawals, fee_rate) = tinypay::get_system_stats(usdc_metadata);
        assert!(total_deposits == 0, 2);
        assert!(total_withdrawals == 0, 3);
        assert!(fee_rate == 100, 4); // 1% fee
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    fun test_deposit_functionality(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let user1_addr = signer::address_of(user1);

        // Mint USDC to user1
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);

        // Check initial USDC balance
        assert!(primary_fungible_store::balance(user1_addr, usdc_metadata) == INITIAL_BALANCE, 1);

        // Deposit into TinyPay
        let tail = b"initial_tail";
        tinypay::deposit(user1, usdc_metadata, DEPOSIT_AMOUNT, tail);

        // Verify deposit
        assert!(tinypay::get_balance(user1_addr, usdc_metadata) == DEPOSIT_AMOUNT, 2);
        assert!(primary_fungible_store::balance(user1_addr, usdc_metadata) == INITIAL_BALANCE - DEPOSIT_AMOUNT, 3);

        // Verify user tail
        let user_tail = tinypay::get_user_tail(user1_addr);
        assert!(user_tail == tail, 4);

        // Verify system stats
        let (total_deposits, _, _) = tinypay::get_system_stats(usdc_metadata);
        assert!(total_deposits == DEPOSIT_AMOUNT, 5);
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    fun test_withdraw_functionality(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let user1_addr = signer::address_of(user1);

        // Setup: Mint and deposit
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);
        let tail = b"initial_tail";
        tinypay::deposit(user1, usdc_metadata, DEPOSIT_AMOUNT, tail);

        // Withdraw funds
        tinypay::withdraw_funds(user1, usdc_metadata, WITHDRAW_AMOUNT);

        // Verify withdrawal
        assert!(tinypay::get_balance(user1_addr, usdc_metadata) == DEPOSIT_AMOUNT - WITHDRAW_AMOUNT, 1);
        assert!(primary_fungible_store::balance(user1_addr, usdc_metadata) ==
                INITIAL_BALANCE - DEPOSIT_AMOUNT + WITHDRAW_AMOUNT, 2);

        // Verify system stats
        let (_, total_withdrawals, _) = tinypay::get_system_stats(usdc_metadata);
        assert!(total_withdrawals == WITHDRAW_AMOUNT, 3);
    }

    #[test(admin = @tinypay, merchant = @0x300, payer = @0x100, recipient = @0x200)]
    fun test_payment_flow(
        admin: &signer,
        merchant: &signer,
        payer: &signer,
        recipient: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let payer_addr = signer::address_of(payer);
        let recipient_addr = signer::address_of(recipient);

        // Setup: Mint and deposit
        usdc::mint(admin, payer_addr, INITIAL_BALANCE);
        let initial_tail = b"initial_tail";
        tinypay::deposit(payer, usdc_metadata, DEPOSIT_AMOUNT, initial_tail);

        // Create payment parameters
        let otp = b"payment_opt";
        let otp_hash = hash::sha2_256(otp);
        let otp_hex = tinypay::bytes_to_hex_ascii(otp_hash);

        // Update user tail to match payment otp
        tinypay::refresh_tail(payer, otp_hex);

        // Merchant precommit
        tinypay::merchant_precommit(merchant, payer_addr, recipient_addr, PAYMENT_AMOUNT, usdc_metadata, otp);

        // Generate commit hash
        let params_bytes = vector::empty<u8>();
        let payer_bytes = std::bcs::to_bytes(&payer_addr);
        let recipient_bytes = std::bcs::to_bytes(&recipient_addr);
        let amount_bytes = std::bcs::to_bytes(&PAYMENT_AMOUNT);
        let otp_bytes = std::bcs::to_bytes(&otp);
        let metadata_addr = object::object_address(&usdc_metadata);
        let metadata_bytes = std::bcs::to_bytes(&metadata_addr);

        params_bytes.append(payer_bytes);
        params_bytes.append(recipient_bytes);
        params_bytes.append(amount_bytes);
        params_bytes.append(otp_bytes);
        params_bytes.append(metadata_bytes);

        let commit_hash = hash::sha2_256(params_bytes);

        // Complete payment
        tinypay::complete_payment(
            merchant,
            otp,
            payer_addr,
            recipient_addr,
            PAYMENT_AMOUNT,
            usdc_metadata,
            commit_hash
        );

        // Verify payment
        let expected_fee = (PAYMENT_AMOUNT * 100) / 10000; // 1% fee
        let expected_recipient_amount = PAYMENT_AMOUNT - expected_fee;

        assert!(tinypay::get_balance(payer_addr, usdc_metadata) == DEPOSIT_AMOUNT - PAYMENT_AMOUNT, 1);
        assert!(primary_fungible_store::balance(recipient_addr, usdc_metadata) == expected_recipient_amount, 2);

        // Verify user tail updated
        let user_tail = tinypay::get_user_tail(payer_addr);
        assert!(user_tail == otp, 3);
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    fun test_payment_limits(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let user1_addr = signer::address_of(user1);

        // Setup: Mint and deposit
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);
        let tail = b"initial_tail";
        tinypay::deposit(user1, usdc_metadata, DEPOSIT_AMOUNT, tail);

        // Set payment limit
        let limit = 30000; // 30K units
        tinypay::set_payment_limit(user1, limit);

        // Verify limits
        let (payment_limit, tail_updates, max_tail_updates) = tinypay::get_user_limits(user1_addr);
        assert!(payment_limit == limit, 1);
        assert!(tail_updates >= 0, 2); // Should have some tail updates from deposit/refresh
        assert!(max_tail_updates == 0, 3); // Default unlimited
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    fun test_tail_management(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);

        let user1_addr = signer::address_of(user1);

        // Initialize user account by making a deposit first
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);
        tinypay::deposit(user1, usdc_metadata, DEPOSIT_AMOUNT, b"initial_tail");

        // Set tail update limit
        tinypay::set_tail_updates_limit(user1, 5);

        // Refresh tail multiple times
        tinypay::refresh_tail(user1, b"tail_1");
        tinypay::refresh_tail(user1, b"tail_2");
        tinypay::refresh_tail(user1, b"tail_3");

        // Verify tail updated
        let user_tail = tinypay::get_user_tail(user1_addr);
        assert!(user_tail == b"tail_3", 1);

        // Verify limits
        let (_, tail_updates, max_tail_updates) = tinypay::get_user_limits(user1_addr);
        assert!(tail_updates >= 4, 2); // At least 4 updates (initial deposit + 3 refresh)
        assert!(max_tail_updates == 5, 3);
    }

    #[test(admin = @tinypay, paymaster = @0x400, payer = @0x100, recipient = @0x200)]
    fun test_paymaster_payment(
        admin: &signer,
        paymaster: &signer,
        payer: &signer,
        recipient: &signer
    ) {
        // Silence unused parameter warning
        let _ = paymaster;
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let payer_addr = signer::address_of(payer);
        let recipient_addr = signer::address_of(recipient);

        // Setup: Mint and deposit
        usdc::mint(admin, payer_addr, INITIAL_BALANCE);
        let initial_tail = b"initial_tail";
        tinypay::deposit(payer, usdc_metadata, DEPOSIT_AMOUNT, initial_tail);

        // Create payment otp and set tail
        let otp = b"paymaster_payment_opt";
        let otp_hash = hash::sha2_256(otp);
        let otp_hex = tinypay::bytes_to_hex_ascii(otp_hash);
        tinypay::refresh_tail(payer, otp_hex);

        // Paymaster can complete payment without precommit (empty commit_hash)
        let empty_commit_hash = vector::empty<u8>();

        // Complete payment as paymaster (admin is also paymaster by default)
        tinypay::complete_payment(
            admin, // Using admin as paymaster
            otp,
            payer_addr,
            recipient_addr,
            PAYMENT_AMOUNT,
            usdc_metadata,
            empty_commit_hash
        );

        // Verify payment completed
        let expected_fee = (PAYMENT_AMOUNT * 100) / 10000; // 1% fee
        let expected_recipient_amount = PAYMENT_AMOUNT - expected_fee;

        assert!(tinypay::get_balance(payer_addr, usdc_metadata) == DEPOSIT_AMOUNT - PAYMENT_AMOUNT, 1);
        assert!(primary_fungible_store::balance(recipient_addr, usdc_metadata) == expected_recipient_amount, 2);
    }

    #[test(admin = @tinypay)]
    #[expected_failure(abort_code = 10, location = tinypay::tinypay)]
    fun test_unsupported_asset_error(admin: &signer) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();

        // Don't add asset support
        let admin_addr = signer::address_of(admin);

        // Try to deposit without asset support - should fail
        usdc::mint(admin, admin_addr, INITIAL_BALANCE);
        tinypay::deposit(admin, usdc_metadata, DEPOSIT_AMOUNT, b"tail");
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    #[expected_failure(abort_code = 1, location = tinypay::tinypay)]
    fun test_insufficient_balance_error(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let user1_addr = signer::address_of(user1);

        // Setup: Mint and deposit small amount
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);
        tinypay::deposit(user1, usdc_metadata, 1000, b"tail"); // Small deposit

        // Try to withdraw more than balance - should fail
        tinypay::withdraw_funds(user1, usdc_metadata, 2000);
    }

    #[test(admin = @tinypay, user1 = @0x100)]
    fun test_multiple_deposits_and_withdrawals(
        admin: &signer,
        user1: &signer
    ) {
        // Setup
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@aptos_framework));
        tinypay::init_system(admin);
        usdc::init_for_test(admin);
        let usdc_metadata = usdc::get_metadata();
        tinypay::add_asset_support(admin, usdc_metadata);

        let user1_addr = signer::address_of(user1);

        // Mint USDC
        usdc::mint(admin, user1_addr, INITIAL_BALANCE);

        // Multiple deposits
        tinypay::deposit(user1, usdc_metadata, 10000, b"tail1");
        tinypay::deposit(user1, usdc_metadata, 20000, b"tail2");
        tinypay::deposit(user1, usdc_metadata, 30000, b"tail3");

        // Check total balance
        assert!(tinypay::get_balance(user1_addr, usdc_metadata) == 60000, 1);

        // Multiple withdrawals
        tinypay::withdraw_funds(user1, usdc_metadata, 5000);
        tinypay::withdraw_funds(user1, usdc_metadata, 15000);

        // Check remaining balance
        assert!(tinypay::get_balance(user1_addr, usdc_metadata) == 40000, 2);

        // Verify system stats
        let (total_deposits, total_withdrawals, _) = tinypay::get_system_stats(usdc_metadata);
        assert!(total_deposits == 60000, 3);
        assert!(total_withdrawals == 20000, 4);
    }
}
