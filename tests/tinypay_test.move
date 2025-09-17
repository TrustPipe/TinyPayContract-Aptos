#[test_only]
module tinypay::tinypay_test {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use tinypay::tinypay;

    fun setup_test(): (signer, signer, signer) {
        let admin = account::create_account_for_test(@tinypay);
        let user = account::create_account_for_test(@0x123);
        let merchant = account::create_account_for_test(@0x456);

        // Initialize AptosCoin with system account
        let aptos_framework = account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);

        // Register accounts with APT
        coin::register<AptosCoin>(&admin);
        coin::register<AptosCoin>(&user);
        coin::register<AptosCoin>(&merchant);

        // Mint and distribute APT coins
        let admin_apt = coin::mint<AptosCoin>(1000000000, &mint_cap); // 10 APT
        let user_apt = coin::mint<AptosCoin>(1000000000, &mint_cap); // 10 APT
        let merchant_apt = coin::mint<AptosCoin>(1000000000, &mint_cap); // 10 APT

        // Deposit coins
        coin::deposit<AptosCoin>(signer::address_of(&admin), admin_apt);
        coin::deposit<AptosCoin>(signer::address_of(&user), user_apt);
        coin::deposit<AptosCoin>(signer::address_of(&merchant), merchant_apt);

        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        // Initialize TinyPay system (automatically supports APT)
        tinypay::init_system(&admin);

        (admin, user, merchant)
    }

    // ========== 基础功能测试 ==========

    #[test]
    fun test_apt_deposit_basic() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 100000000; // 1 APT in octas
        let tail = b"test_tail_123";

        // Check initial balance
        let initial_balance = coin::balance<AptosCoin>(signer::address_of(&user));

        // Deposit APT with tail
        tinypay::deposit<AptosCoin>(&user, deposit_amount, tail);

        // Verify TinyPay balance increased
        let tinypay_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&user));
        assert!(tinypay_balance == deposit_amount, 1);

        // Verify user's coin balance decreased
        let final_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        assert!(final_balance == initial_balance - deposit_amount, 2);
    }

    #[test]
    fun test_apt_withdraw() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 200000000; // 2 APT
        let withdraw_amount = 100000000; // 1 APT
        let tail = b"withdraw_tail";

        // First deposit
        tinypay::deposit<AptosCoin>(&user, deposit_amount, tail);

        // Check balance before withdrawal
        let initial_coin_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let initial_tinypay_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&user));

        // Withdraw
        tinypay::withdraw_funds<AptosCoin>(&user, withdraw_amount);

        // Verify balances
        let final_coin_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        let final_tinypay_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&user));

        assert!(final_coin_balance == initial_coin_balance + withdraw_amount, 1);
        assert!(final_tinypay_balance == initial_tinypay_balance - withdraw_amount, 2);
    }

    #[test]
    fun test_multiple_deposits() {
        let (_admin, user, _merchant) = setup_test();
        let first_amount = 100000000; // 1 APT
        let second_amount = 150000000; // 1.5 APT
        let tail = b"multi_deposit_tail";

        // First deposit
        tinypay::deposit<AptosCoin>(&user, first_amount, tail);
        let balance_after_first = tinypay::get_balance<AptosCoin>(signer::address_of(&user));
        assert!(balance_after_first == first_amount, 1);

        // Second deposit
        tinypay::deposit<AptosCoin>(&user, second_amount, tail);
        let balance_after_second = tinypay::get_balance<AptosCoin>(signer::address_of(&user));
        assert!(balance_after_second == first_amount + second_amount, 2);
    }

    // ========== 多用户测试 ==========

    #[test]
    fun test_merchant_transactions() {
        let (_admin, user, merchant) = setup_test();
        let user_deposit = 500000000; // 5 APT
        let merchant_deposit = 300000000; // 3 APT
        let tail = b"merchant_test";

        // Both user and merchant deposit
        tinypay::deposit<AptosCoin>(&user, user_deposit, tail);
        tinypay::deposit<AptosCoin>(&merchant, merchant_deposit, tail);

        // Verify separate balances
        let user_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&user));
        let merchant_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&merchant));
        
        assert!(user_balance == user_deposit, 1);
        assert!(merchant_balance == merchant_deposit, 2);
    }

    // ========== Tail 功能测试 ==========

    #[test]
    fun test_tail_update() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 100000000; // 1 APT
        let first_tail = b"first_tail";
        let second_tail = b"second_tail";

        // Deposit with first tail
        tinypay::deposit<AptosCoin>(&user, deposit_amount, first_tail);
        
        // Deposit with different tail (should update tail)
        tinypay::deposit<AptosCoin>(&user, deposit_amount, second_tail);

        // Verify balance is correct
        let final_balance = tinypay::get_balance<AptosCoin>(signer::address_of(&user));
        assert!(final_balance == deposit_amount * 2, 1);
    }

    // ========== 系统功能测试 ==========

    #[test]
    fun test_coin_support_check() {
        let (_admin, _user, _merchant) = setup_test();

        // Check that APT is supported by default
        assert!(tinypay::is_coin_supported<AptosCoin>(), 1);
    }

    // ========== 错误处理测试 ==========

    #[test]
    #[expected_failure(abort_code = 2, location = tinypay::tinypay)]
    fun test_zero_amount_deposit() {
        let (_admin, user, _merchant) = setup_test();
        let tail = b"zero_test";

        // This should fail with E_INVALID_AMOUNT
        tinypay::deposit<AptosCoin>(&user, 0, tail);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = tinypay::tinypay)]
    fun test_account_not_initialized_withdrawal() {
        let (_admin, user, _merchant) = setup_test();
        
        // Try to withdraw without initializing account first
        // This should fail with E_ACCOUNT_NOT_INITIALIZED
        tinypay::withdraw_funds<AptosCoin>(&user, 100000000);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = tinypay::tinypay)]
    fun test_insufficient_balance_withdrawal() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 100000000; // 1 APT
        let withdraw_amount = 200000000; // 2 APT (more than deposited)

        // Deposit then try to withdraw more than available
        tinypay::deposit<AptosCoin>(&user, deposit_amount, b"test_tail");
        tinypay::withdraw_funds<AptosCoin>(&user, withdraw_amount);
    }

    #[test]
    #[expected_failure(abort_code = 11, location = tinypay::tinypay)]
    fun test_add_duplicate_coin_support() {
        let (admin, _user, _merchant) = setup_test();

        // Try to add APT support again - should fail since it's already supported
        tinypay::add_coin_support<AptosCoin>(&admin);
    }
}
