#[test_only]
module tinypay::tinypay_test {
    use std::signer;
    // string module no longer needed since we use vector<u8> for hashes
    use std::bcs;
    use std::vector;
    use std::hash;
    use aptos_framework::account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use tinypay::tinypay;

    fun setup_test(): (signer, signer, signer) {
        let aptos_framework = account::create_account_for_test(@0x1);
        let admin = account::create_account_for_test(@0x42); // Must match dev address in Move.toml
        let user = account::create_account_for_test(@0x100);
        let merchant = account::create_account_for_test(@0x200);

        // Initialize AptosCoin
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);

        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        // Initialize TinyPay system
        tinypay::init_system(&admin);

        // Fund accounts
        coin::register<AptosCoin>(&user);
        coin::register<AptosCoin>(&merchant);

        // Mint coins for testing
        let user_coins = coin::mint<AptosCoin>(10000000000, &mint_cap); // 100 APT
        let merchant_coins = coin::mint<AptosCoin>(1000000000, &mint_cap); // 10 APT

        coin::deposit(signer::address_of(&user), user_coins);
        coin::deposit(signer::address_of(&merchant), merchant_coins);

        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        (admin, user, merchant)
    }

    #[test]
    fun test_deposit_with_tail() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 100000000; // 1 APT in octas
        let tail = b"test_tail_123";

        // Check initial balance
        let initial_balance = coin::balance<AptosCoin>(signer::address_of(&user));

        // Deposit APT with tail
        tinypay::deposit(&user, deposit_amount, tail);

        // Verify TinyPay balance increased
        assert!(tinypay::get_balance(signer::address_of(&user)) == deposit_amount, 1);

        // Verify tail was set
        assert!(tinypay::get_user_tail(signer::address_of(&user)) == tail, 2);

        // Verify APT balance decreased
        let final_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        assert!(final_balance == initial_balance - deposit_amount, 3);

        // Verify tail update count increased
        let (_, tail_update_count, _) = tinypay::get_user_limits(signer::address_of(&user));
        assert!(tail_update_count == 1, 4);
    }

    #[test]
    fun test_refresh_tail() {
        let (_admin, user, _merchant) = setup_test();
        let initial_tail = b"initial_tail";
        let new_tail = b"refreshed_tail";

        // Deposit with initial tail
        tinypay::deposit(&user, 100000000, initial_tail);

        // Verify initial state
        assert!(tinypay::get_user_tail(signer::address_of(&user)) == initial_tail, 1);
        let (_, tail_count_before, _) = tinypay::get_user_limits(signer::address_of(&user));
        assert!(tail_count_before == 1, 2);

        // Refresh tail
        tinypay::refresh_tail(&user, new_tail);

        // Verify tail was updated
        assert!(tinypay::get_user_tail(signer::address_of(&user)) == new_tail, 3);
        let (_, tail_count_after, _) = tinypay::get_user_limits(signer::address_of(&user));
        assert!(tail_count_after == 2, 4);
    }

    #[test]
    fun test_add_funds() {
        let (_admin, user, _merchant) = setup_test();
        let initial_deposit = 100000000; // 1 APT
        let additional_funds = 200000000; // 2 APT
        let tail = b"test_tail";

        // Initialize account and deposit initial funds
        tinypay::deposit(&user, initial_deposit, tail);

        // Verify initial balance
        assert!(tinypay::get_balance(signer::address_of(&user)) == initial_deposit, 1);

        // Add more funds
        tinypay::add_funds(&user, additional_funds);

        // Verify balance increased
        let expected_balance = initial_deposit + additional_funds;
        assert!(tinypay::get_balance(signer::address_of(&user)) == expected_balance, 2);
    }

    #[test]
    fun test_withdraw_funds() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 300000000; // 3 APT
        let withdraw_amount = 100000000; // 1 APT
        let tail = b"test_tail";

        // Initialize account and deposit funds
        tinypay::deposit(&user, deposit_amount, tail);

        // Check initial balance
        assert!(tinypay::get_balance(signer::address_of(&user)) == deposit_amount, 1);

        // Check initial APT balance
        let initial_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));

        // Withdraw funds
        tinypay::withdraw_funds(&user, withdraw_amount);

        // Verify TinyPay balance decreased
        let expected_balance = deposit_amount - withdraw_amount;
        assert!(tinypay::get_balance(signer::address_of(&user)) == expected_balance, 2);

        // Verify APT balance increased
        let final_apt_balance = coin::balance<AptosCoin>(signer::address_of(&user));
        assert!(final_apt_balance == initial_apt_balance + withdraw_amount, 3);
    }

    #[test]
    #[expected_failure(abort_code = tinypay::E_INVALID_AMOUNT)]
    fun test_deposit_zero_amount() {
        let (_admin, user, _merchant) = setup_test();

        // Try to deposit zero amount - should fail
        tinypay::deposit(&user, 0, b"test_tail");
    }

    #[test]
    fun test_admin_update_fee_rate() {
        let (admin, _user, _merchant) = setup_test();
        let new_fee_rate = 200; // 2%

        // Update fee rate as admin
        tinypay::update_fee_rate(&admin, new_fee_rate);

        // Verify fee rate was updated
        let (_, _, fee_rate) = tinypay::get_system_stats();
        assert!(fee_rate == new_fee_rate, 1);
    }

    #[test]
    #[expected_failure(abort_code = tinypay::E_NOT_ADMIN)]
    fun test_non_admin_update_fee_rate() {
        let (_admin, user, _merchant) = setup_test();
        let new_fee_rate = 200;

        // Try to update fee rate as non-admin - should fail
        tinypay::update_fee_rate(&user, new_fee_rate);
    }

    #[test]
    fun test_get_system_stats() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 300000000; // 3 APT

        // Initialize account and deposit
        tinypay::deposit(&user, deposit_amount, b"test_tail");

        // Check system stats
        let (total_deposits, total_withdrawals, fee_rate) = tinypay::get_system_stats();
        assert!(total_deposits == deposit_amount, 1);
        assert!(total_withdrawals == 0, 2);
        assert!(fee_rate == 100, 3); // Default 1% fee
    }

    #[test]
    fun test_set_payment_limit() {
        let (_admin, user, _merchant) = setup_test();
        let limit = 100000000; // 1 APT limit

        // deposit to init fist
        tinypay::deposit(&user, 100000000, b"test_tail");

        // Set payment limit
        tinypay::set_payment_limit(&user, limit);

        // Verify limit was set
        let (payment_limit, _, _) = tinypay::get_user_limits(signer::address_of(&user));
        assert!(payment_limit == limit, 1);
    }

    #[test]
    fun test_set_tail_updates_limit() {
        let (_admin, user, _merchant) = setup_test();
        let limit = 5; // 5 tail updates max

        // deposit to init fist
        tinypay::deposit(&user, 100000000, b"test_tail");

        // Set tail updates limit
        tinypay::set_tail_updates_limit(&user, limit);

        // Verify limit was set
        let (_, _, max_tail_updates) = tinypay::get_user_limits(signer::address_of(&user));
        assert!(max_tail_updates == limit, 1);
    }

    #[test]
    #[expected_failure(abort_code = tinypay::E_TAIL_UPDATES_LIMIT_EXCEEDED)]
    fun test_refresh_tail_limit_exceeded() {
        let (_admin, user, _merchant) = setup_test();
        let limit = 2; // Only 2 tail updates allowed

        // deposit to init fist
        tinypay::deposit(&user, 100000000, b"test_tail");

        // Set tail updates limit
        tinypay::set_tail_updates_limit(&user, limit);

        // Deposit with first tail update
        tinypay::deposit(&user, 100000000, b"tail1");

        // Refresh tail (second update)
        tinypay::refresh_tail(&user, b"tail2");

        // Try to refresh again (third update) - should fail
        tinypay::refresh_tail(&user, b"tail3");
    }

    #[test]
    #[expected_failure(abort_code = tinypay::E_INSUFFICIENT_BALANCE)]
    fun test_withdraw_insufficient_balance() {
        let (_admin, user, _merchant) = setup_test();
        let deposit_amount = 100000000; // 1 APT
        let withdraw_amount = 200000000; // 2 APT (more than deposited)

        // deposit
        tinypay::deposit(&user, deposit_amount, b"test_tail");

        // Try to withdraw more than available - should fail
        tinypay::withdraw_funds(&user, withdraw_amount);
    }

    #[test]
    fun test_two_phase_payment() {
        let (_admin, user, merchant) = setup_test();
        let deposit_amount = 500000000; // 5 APT
        let payment_amount = 100000000; // 1 APT
        let opt_value = b"test_opt_value";

        // deposit with initial tail that matches hash(opt)
        // First calculate what the tail should be (hash of opt)
        let opt_bytes = bcs::to_bytes(&opt_value);
        let tail_hash_bytes = hash::sha2_256(opt_bytes);
        let initial_tail = tail_hash_bytes;
        
        tinypay::deposit(&user, deposit_amount, initial_tail);

        // Phase 1: Merchant pre-commit
        // Generate commit hash from payment parameters (payer, recipient, amount, opt)
        let params_bytes = vector::empty<u8>();
        let payer_bytes = bcs::to_bytes(&signer::address_of(&user));
        let recipient_bytes = bcs::to_bytes(&signer::address_of(&merchant));
        let amount_bytes = bcs::to_bytes(&payment_amount);
        let opt_bytes_for_hash = bcs::to_bytes(&opt_value);

        params_bytes.append(payer_bytes);
        params_bytes.append(recipient_bytes);
        params_bytes.append(amount_bytes);
        params_bytes.append(opt_bytes_for_hash);

        let commit_hash_bytes = hash::sha2_256(params_bytes);
        let commit_hash = commit_hash_bytes;

        tinypay::merchant_precommit(&merchant, commit_hash);

        // Verify user balance before payment
        assert!(tinypay::get_balance(signer::address_of(&user)) == deposit_amount, 1);

        // Phase 2: User completes payment with opt value
        let merchant_initial_balance = coin::balance<AptosCoin>(signer::address_of(&merchant));
        
        tinypay::complete_payment(&user, opt_value, signer::address_of(&merchant), payment_amount, commit_hash);

        // Verify payment was successful
        let user_balance_after = tinypay::get_balance(signer::address_of(&user));
        assert!(user_balance_after == deposit_amount - payment_amount, 2);

        // Verify merchant received payment (minus fee)
        let merchant_final_balance = coin::balance<AptosCoin>(signer::address_of(&merchant));
        let fee = (payment_amount * 100) / 10000; // 1% fee
        let expected_merchant_amount = payment_amount - fee;
        assert!(merchant_final_balance == merchant_initial_balance + expected_merchant_amount, 3);

        // Verify tail was updated to opt value
        assert!(tinypay::get_user_tail(signer::address_of(&user)) == opt_value, 4);
    }
}
