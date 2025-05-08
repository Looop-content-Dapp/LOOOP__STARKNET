use starknet::{ContractAddress, contract_address_const, ClassHash, get_block_timestamp};
use openzeppelin::token::erc721::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
// use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp
};
use core::num::traits::Zero;
use loop_starknet::mockUSDC::USDC;
use loop_starknet::factory::TribesNftFactory;
use loop_starknet::vault::Vault;
use loop_starknet::vault::Vault::PassStatus;
use loop_starknet::nfts::tribes_nft::TribesNFT;
use loop_starknet::interfaces::{
    ITribesFactoryDispatcher, ITribesFactoryDispatcherTrait, IVaultDispatcher,
    IVaultDispatcherTrait, IUSDCTokenDispatcher, IUSDCTokenDispatcherTrait, IERC721Dispatcher, IERC721DispatcherTrait
};

fn deploy_token() -> ContractAddress {
    let owner = contract_address_const::<'owner'>();
    let mut calldata = ArrayTrait::new();

    owner.serialize(ref calldata);
    let contract = declare("USDC").unwrap().contract_class();
    let (USDC_address, _) = contract.deploy(@calldata).unwrap();
    USDC_address
}

fn deploy_factory_contract() -> ContractAddress {
    let owner = contract_address_const::<'owner'>();
    let protocol_vault = contract_address_const::<'protocol_vault'>();
    let house_perc: u32 = 30_u32;
    let vault_classhash = declare("Vault").unwrap().contract_class();
    let tribes_classhash = declare("TribesNFT").unwrap().contract_class();
    let USDC_address = deploy_token();

    let mut calldata = ArrayTrait::new();
    owner.serialize(ref calldata);
    protocol_vault.serialize(ref calldata);
    house_perc.serialize(ref calldata);
    vault_classhash.serialize(ref calldata);
    tribes_classhash.serialize(ref calldata);
    USDC_address.serialize(ref calldata);

    let contract = declare("TribesNftFactory").unwrap().contract_class();
    let (factory_contract_address, _) = contract.deploy(@calldata).unwrap();
    factory_contract_address
}


#[test]
fn test_deploy_factory() {
    let factory_address = deploy_factory_contract();
    assert(factory_address.is_non_zero(), 'zero factory contract');
}

#[test]
fn test_create_collection() {
    let pauser = contract_address_const::<'pauser'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 8000000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";

    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);

    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);

    assert!(tribes_nft_address.is_non_zero(), "NFT address is zero");
    assert!(vault_address.is_non_zero(), "NFT address is zero");
}


fn create_test_collection(
    factory_address: ContractAddress, pauser: ContractAddress, payment_token: ContractAddress
) -> (ContractAddress, ContractAddress) {
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 8000000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            payment_token,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);

    (tribes_nft_address, vault_address)
}


#[test]
fn test_add_supported_token() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let token = deploy_token();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Get initial payment tokens
    let initial_tokens = factory_dispatcher.get_payment_tokens();
    let initial_count = initial_tokens.len();

    // Add a new supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(token);
    stop_cheat_caller_address(factory_address);

    // Verify the token was added
    let updated_tokens = factory_dispatcher.get_payment_tokens();
    assert(updated_tokens.len() == initial_count + 1, 'Token not added');
}


#[test]
fn test_update_royalties() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Update royalties
    let new_house_percentage: u32 = 40;
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.update_royalties(new_house_percentage);
    stop_cheat_caller_address(factory_address);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_update_royalties_should_panic() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Update royalties
    let new_house_percentage: u32 = 40;
    factory_dispatcher.update_royalties(new_house_percentage);
}


#[test]
fn test_get_payment_tokens() {
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Verify initial payment token (from constructor)
    let initial_tokens = factory_dispatcher.get_payment_tokens();
    assert(initial_tokens.len() == 1, 'Wrong initial token count');

    let token: ContractAddress = deploy_token();

    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(token);
    stop_cheat_caller_address(factory_address);

    let all_tokens = factory_dispatcher.get_payment_tokens();
    assert(all_tokens.len() == 2, 'Wrong token count');

    assert(*all_tokens[1] == token, 'Wrong token at index 1');
}


#[test]
fn test_get_artist_collections() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let artist1 = contract_address_const::<'pauser'>();
    let artist2 = contract_address_const::<'artist2'>();
    let payment_token = deploy_token();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Add payment token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(payment_token);
    stop_cheat_caller_address(factory_address);

    // Create collections for artist1
    create_test_collection(factory_address, artist1, payment_token);

    // Create collection with different symbol for artist1
    let name = "SecondCollection";
    let symbol = "TEST2";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 8000000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Second test collection";

    start_cheat_caller_address(factory_address, artist1);
    factory_dispatcher
        .create_collection(
            artist2,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            payment_token,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);

    // Get artist1 collections
    let artist1_collections = factory_dispatcher.get_artist_collections(artist1);
    assert(artist1_collections.len() == 1, 'Wrong artist1 collection count');

    // Get artist2 collections
    let artist2_collections = factory_dispatcher.get_artist_collections(artist2);
    assert(artist2_collections.len() == 1, 'Wrong artist2 collection count');

    // Check collection details
    assert(*artist1_collections[0].artist == artist1, 'Wrong artist in collection');
    assert(artist2_collections[0].symbol == @"TEST2", 'Wrong symbol in collection');

    // Get collections for non-existent artist
    let non_artist = contract_address_const::<'non_artist'>();
    let non_artist_collections = factory_dispatcher.get_artist_collections(non_artist);
    assert(non_artist_collections.len() == 0, 'Should return empty array');
}


#[test]
fn test_get_all_collections() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let artist = contract_address_const::<'pauser'>();
    let payment_token = deploy_token();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Add payment token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(payment_token);
    stop_cheat_caller_address(factory_address);

    // Initially should have no collections
    let initial_collections = factory_dispatcher.get_all_collections();
    assert(initial_collections.len() == 0, 'Should start with no coll');

    // Create multiple collections
    create_test_collection(factory_address, artist, payment_token);

    // Get all collections
    let all_collections = factory_dispatcher.get_all_collections();
    assert(all_collections.len() == 1, 'Wrong collection count');

    // Verify collection order (by ID)
    assert(*all_collections[0].collection_id == 1, 'Wrong first collection ID');

    // Create another collection
    let name = "Second Collection";
    let symbol = "TEST2";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 8000000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Second test collection";

    start_cheat_caller_address(factory_address, artist);
    factory_dispatcher
        .create_collection(
            artist,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            payment_token,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);

    // Verify the collection was added
    let updated_collections = factory_dispatcher.get_all_collections();
    assert(updated_collections.len() == 2, 'Collection not added');
}


#[test]
fn test_withdraw() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let receiver = contract_address_const::<'receiver'>();
    let payment_token = deploy_token();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Send some tokens to the factory contract
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: payment_token };
    let amount: u256 = 1000000_u256;

    start_cheat_caller_address(payment_token, owner);
    token_dispatcher.transfer(factory_address, amount);
    let balance_before = token_dispatcher.balance_of(factory_address);
    stop_cheat_caller_address(payment_token);

    assert(balance_before == amount, 'transfer failed');

    // Withdraw as owner
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.withdraw(receiver, payment_token, amount);
    stop_cheat_caller_address(factory_address);

    // Verify receiver got the tokens
    let balance = token_dispatcher.balance_of(factory_address);
    assert(balance == 0, 'Tokens not received');
}

#[test]
#[should_panic(expected: 'symbol taken')]
fn test_symbol_should_panic() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let artist = contract_address_const::<'pauser'>();
    let payment_token = deploy_token();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Add payment token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(payment_token);
    stop_cheat_caller_address(factory_address);

    // Create first collection
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 8000000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";

    start_cheat_caller_address(factory_address, artist);
    factory_dispatcher
        .create_collection(
            artist,
            name.clone(),
            symbol.clone(),
            duration,
            grace_period,
            passcost,
            payment_address,
            payment_token,
            collection_details.clone(),
        );

    // Try creating another collection with the same symbol (should fail)
    let name2: ByteArray = "SecondCollection";
    factory_dispatcher
        .create_collection(
            artist,
            name2.clone(),
            symbol.clone(), // Same symbol
            duration,
            grace_period,
            passcost,
            payment_address,
            payment_token,
            collection_details.clone(),
        );
    stop_cheat_caller_address(factory_address);
}

#[test]
fn test_mint_pass() {
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";

    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);

    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);

    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let amount: u256 = 1_000_000_u256;

    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };

    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);

    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);

    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);

    let balance_of_artist = token_dispatcher.balance_of(payment_address);
    assert!(balance_of_artist == 7000, "Inaccurate artist bal");
    
    let balance_of_factory = token_dispatcher.balance_of(factory_address);
    assert!(balance_of_factory == 3000, "Inaccurate platform bal");
} 


#[test]
fn test_renew_pass() {
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // First mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Record balances after first mint
    let artist_balance_after_mint = token_dispatcher.balance_of(payment_address);
    let factory_balance_after_mint = token_dispatcher.balance_of(factory_address);
    
    // Now renew the pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.renew_pass(tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Check balances after renewal
    let artist_balance_after_renewal = token_dispatcher.balance_of(payment_address);
    let factory_balance_after_renewal = token_dispatcher.balance_of(factory_address);
    
    // Verify artist received additional 70% of pass cost
    assert!(
        artist_balance_after_renewal == artist_balance_after_mint + 7000, 
        "Artist did not receive correct renewal payment"
    );
    
    // Verify factory received additional 30% of pass cost
    assert!(
        factory_balance_after_renewal == factory_balance_after_mint + 3000,
        "Factory did not receive correct renewal fee"
    );
    
    // Check pass validity after renewal
    let user_pass = vault_dispatcher.get_user_pass(user);
    assert!(user_pass.is_valid, "Pass should be valid after renewal");
    
    // Check artist stats were updated
    let artist_info = vault_dispatcher.get_artist_info(pauser);
    assert!(artist_info.total_passes == 2, "Artist total passes not updated correctly");
    assert!(artist_info.active_passes == 2, "Artist active passes not updated correctly");
    assert!(
        artist_info.total_royalties_earned == 14000, 
        "Artist royalties not updated correctly"
    );
}


#[test]
#[should_panic(expected: 'user record not found')]
fn test_renew_pass_should_panic_user_not_found() {
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // First mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Record balances after first mint
    let artist_balance_after_mint = token_dispatcher.balance_of(payment_address);
    let factory_balance_after_mint = token_dispatcher.balance_of(factory_address);
    
    // Now renew the pass by guest user
    vault_dispatcher.renew_pass(tribes_nft_address);
    
}


#[test]
fn test_check_pass_status() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 86400; // 1 day duration for easier testing
    let grace_period: u64 = 3600; // 1 hour grace period
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // Mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Get tribe details to get tribe ID
    let tribe_details = vault_dispatcher.get_tribe_info(tribes_nft_address);
    let tribe_id = tribe_details.tribe_id;
    
    // Check initial status (should be Active)
    let status = vault_dispatcher.check_pass_status(user, tribe_id);
    assert!(status, "tribe status not valid");
   
    
    // Fast forward time to within grace period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp(vault_address, current_time + duration + 1000);
    let status = vault_dispatcher.check_pass_status(user, tribe_id);
    assert!(status, "tribe status not in grace period");
    
    // Fast forward beyond grace period
    start_cheat_block_timestamp(vault_address, current_time + duration + grace_period + 1000);
    
    // Check status after grace period (should be Expired)
    let status = vault_dispatcher.check_pass_status(user, tribe_id);
    assert!(!status, "tribe status still valid");
    
    stop_cheat_block_timestamp(vault_address);
}

#[test]
fn test_burn_expired_pass() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 86400; // 1 day duration
    let grace_period: u64 = 3600; // 1 hour grace period
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
    .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    let nft_dispatcher = ERC721ABIDispatcher { contract_address: tribes_nft_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // Mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    let nft_balance_of_user = nft_dispatcher.balance_of(user);
    println!("nft balance of user: {}", nft_balance_of_user);
    assert!(nft_balance_of_user == 1, "incorrect nft balance before burn");
    stop_cheat_caller_address(vault_address);
    
    // Get tribe details to get tribe ID
    let tribe_details = vault_dispatcher.get_tribe_info(tribes_nft_address);
    let tribe_id = tribe_details.tribe_id;
    
    
    // Fast forward beyond pass expiration and grace period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp(vault_address, current_time + duration + grace_period + 10000);
    
    //approve nft to artist
    start_cheat_caller_address(tribes_nft_address, user);
    nft_dispatcher.approve(vault_address, tribe_id.into());
    stop_cheat_caller_address(tribes_nft_address);

    // Now burn the expired pass
    start_cheat_caller_address(vault_address, pauser);

    vault_dispatcher.burn_expired_pass(tribe_id, user);
    let nft_balance_of_user_after_burn = nft_dispatcher.balance_of(user);
    println!("nft balance of user after burn: {}", nft_balance_of_user_after_burn);
    assert!(nft_balance_of_user_after_burn == 0, "incorrect nft balance after burn");
    stop_cheat_caller_address(vault_address);

    stop_cheat_block_timestamp(vault_address);
}


#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_burn_expired_pass_should_panic_caller_is_not_the_owner() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 86400; // 1 day duration
    let grace_period: u64 = 3600; // 1 hour grace period
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
    .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    let nft_dispatcher = ERC721ABIDispatcher { contract_address: tribes_nft_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // Mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    let nft_balance_of_user = nft_dispatcher.balance_of(user);
    assert!(nft_balance_of_user == 1, "incorrect nft balance before burn");
    stop_cheat_caller_address(vault_address);
    
    // Get tribe details to get tribe ID
    let tribe_details = vault_dispatcher.get_tribe_info(tribes_nft_address);
    let tribe_id = tribe_details.tribe_id;
    
    
    // Fast forward beyond pass expiration and grace period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp(vault_address, current_time + duration + grace_period + 10000);
    
    //approve nft to artist
    start_cheat_caller_address(tribes_nft_address, user);
    nft_dispatcher.approve(vault_address, tribe_id.into());
    stop_cheat_caller_address(tribes_nft_address);

    // Now burn the expired pass by non-owner
    vault_dispatcher.burn_expired_pass(tribe_id, user);
    
    stop_cheat_block_timestamp(vault_address);
}


#[test]
fn test_get_tribe_info() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Get tribe info and verify values
    let tribe_info = vault_dispatcher.get_tribe_info(tribes_nft_address);
    
    assert!(tribe_info.artist == pauser, "Incorrect artist address");
    assert!(tribe_info.tribe_nft_address == tribes_nft_address, "Incorrect NFT address");
    assert!(tribe_info.pass_cost == passcost, "Incorrect pass cost");
    assert!(tribe_info.pass_duration == duration, "Incorrect pass duration");
    assert!(tribe_info.grace_period == grace_period, "Incorrect grace period");
    assert!(tribe_info.payment_address == payment_address, "Incorrect payment address");
    assert!(tribe_info.artist_percentage == 70, "Incorrect artist percentage");
    assert!(tribe_info.house_percentage == 30, "Incorrect house percentage");
}

#[test]
fn test_get_artist_info() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Check initial artist info (before any passes)
    let initial_artist_info = vault_dispatcher.get_artist_info(pauser);
    assert!(initial_artist_info.artist == pauser, "Incorrect artist address");
    assert!(initial_artist_info.total_royalties_earned == 0, "Initial royalties should be 0");
    assert!(initial_artist_info.total_passes == 0, "Initial passes should be 0");
    assert!(initial_artist_info.active_passes == 0, "Initial active passes should be 0");
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // Mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Check artist info after minting
    let artist_info_after_mint = vault_dispatcher.get_artist_info(pauser);
    assert!(artist_info_after_mint.total_royalties_earned == 7000, "Incorrect royalties after mint");
    assert!(artist_info_after_mint.total_passes == 1, "Should have 1 total pass");
    assert!(artist_info_after_mint.active_passes == 1, "Should have 1 active pass");
}

#[test]
fn test_get_user_pass() {
    // Setup similar to previous tests
    let pauser = contract_address_const::<'pauser'>();
    let user = contract_address_const::<'user'>();
    let owner = contract_address_const::<'owner'>();
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let grace_period: u64 = duration + 3600;
    let passcost: u256 = 10000_u256;
    let payment_address = contract_address_const::<'payment_address'>();
    let collection_details: ByteArray = "Test collection description";
    
    // Deploy contracts
    let factory_address = deploy_factory_contract();
    let USDC_address = deploy_token();
    
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };
    
    // Add supported token
    start_cheat_caller_address(factory_address, owner);
    factory_dispatcher.add_supported_token(USDC_address);
    stop_cheat_caller_address(factory_address);
    
    // Create collection
    start_cheat_caller_address(factory_address, pauser);
    let (tribes_nft_address, vault_address) = factory_dispatcher
        .create_collection(
            pauser,
            name,
            symbol,
            duration,
            grace_period,
            passcost,
            payment_address,
            USDC_address,
            collection_details,
        );
    stop_cheat_caller_address(factory_address);
    
    let token_dispatcher = IUSDCTokenDispatcher { contract_address: USDC_address };
    let vault_dispatcher = IVaultDispatcher { contract_address: vault_address };
    
    // Give user tokens and approve them for vault
    let amount: u256 = 1_000_000_u256;
    start_cheat_caller_address(USDC_address, owner);
    token_dispatcher.transfer(user, amount);
    stop_cheat_caller_address(USDC_address);
    
    start_cheat_caller_address(USDC_address, user);
    token_dispatcher.approve(vault_address, amount);
    stop_cheat_caller_address(USDC_address);
    
    // Mint a pass
    start_cheat_caller_address(vault_address, user);
    vault_dispatcher.mint_pass(pauser, tribes_nft_address);
    stop_cheat_caller_address(vault_address);
    
    // Get user pass details
    let user_pass = vault_dispatcher.get_user_pass(user);
    
    // Get tribe details to compare token ID
    let tribe_details = vault_dispatcher.get_tribe_info(tribes_nft_address);
    
    assert!(user_pass.tribe_nft_address == tribes_nft_address, "Incorrect NFT address");
    assert!(user_pass.token_id == tribe_details.tribe_id.into(), "Incorrect token ID");
    assert!(user_pass.owner == user, "Incorrect owner address");
    assert!(user_pass.is_valid, "Pass should be valid");

}
