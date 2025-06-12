use core::num::traits::Zero;
use loop_starknet::factory::TribesNftFactory;
use loop_starknet::interfaces::{
    IERC721Dispatcher, IERC721DispatcherTrait, IExternalDispatcher, IExternalDispatcherTrait,
    ITribesFactoryDispatcher, ITribesFactoryDispatcherTrait,
};
use loop_starknet::nfts::tribes_nft::TribesNFT;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress, contract_address_const, get_block_timestamp};


fn deploy_factory_contract() -> ContractAddress {
    let owner = contract_address_const::<'owner'>();
    let house_perc: u32 = 30_u32;
    let erc20_address = deploy_erc20_contract();
    let tribes_classhash = declare("TribesNFT").unwrap().contract_class();
    let mut calldata = ArrayTrait::new();
    owner.serialize(ref calldata);
    house_perc.serialize(ref calldata);
    tribes_classhash.serialize(ref calldata);
    erc20_address.serialize(ref calldata);

    let contract = declare("TribesNftFactory").unwrap().contract_class();
    let (factory_contract_address, _) = contract.deploy(@calldata).unwrap();
    factory_contract_address
}

fn deploy_erc20_contract() -> ContractAddress {
    let owner = contract_address_const::<'owner'>();
    let house_perc: u32 = 30_u32;

    let sender: ContractAddress = contract_address_const::<'owner'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), 6];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    erc20_address
}

#[test]
fn test_deploy_factory() {
    let factory_address = deploy_factory_contract();
    let erc20_address = deploy_erc20_contract();

    assert(factory_address.is_non_zero(), 'zero factory contract');
    assert(erc20_address.is_non_zero(), 'zero factory contract');
}

#[test]
fn test_create_collection() {
    let pauser = contract_address_const::<'pauser'>();
    let name = "TestCollection";
    let symbol = "TEST";

    let collection_details: ByteArray = "Test collection description";

    let factory_address = deploy_factory_contract();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    let erc20_address = deploy_erc20_contract();

    start_cheat_caller_address(factory_address, pauser);
    let tribes_nft_address = factory_dispatcher
        .create_collection(pauser, name, symbol, collection_details);
    stop_cheat_caller_address(factory_address);

    assert!(tribes_nft_address.is_non_zero(), "NFT address is zero");
}

fn create_test_collection(
    factory_address: ContractAddress, pauser: ContractAddress,
) -> ContractAddress {
    let name = "TestCollection";
    let symbol = "TEST";

    let collection_details: ByteArray = "Test collection description";

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, pauser);
    let tribes_nft_address = factory_dispatcher
        .create_collection(pauser, name, symbol, collection_details);
    stop_cheat_caller_address(factory_address);

    tribes_nft_address
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
    let erc20_address = deploy_erc20_contract();
    let _owner = contract_address_const::<'owner'>();
    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Update royalties
    let new_house_percentage: u32 = 40;
    factory_dispatcher.update_royalties(new_house_percentage);
}

#[test]
fn test_get_artist_collections() {
    // Setup
    let factory_address = deploy_factory_contract();
    let owner = contract_address_const::<'owner'>();
    let artist1 = contract_address_const::<'pauser'>();
    let artist2 = contract_address_const::<'artist2'>();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, owner);
    // Create collections for artist1
    create_test_collection(factory_address, artist1);
    stop_cheat_caller_address(factory_address);

    // Create collection with different symbol for artist1
    let name = "SecondCollection";
    let symbol = "TEST2";

    let collection_details: ByteArray = "Second test collection";

    start_cheat_caller_address(factory_address, artist1);
    factory_dispatcher.create_collection(artist2, name, symbol, collection_details);
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
    let erc20_address = deploy_erc20_contract();
    let owner = contract_address_const::<'owner'>();
    let artist = contract_address_const::<'pauser'>();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Initially should have no collections
    let initial_collections = factory_dispatcher.get_all_collections();
    assert(initial_collections.len() == 0, 'Should start with no coll');

    // Create multiple collections
    create_test_collection(factory_address, artist);

    // Get all collections
    let all_collections = factory_dispatcher.get_all_collections();
    assert(all_collections.len() == 1, 'Wrong collection count');

    // Verify collection order (by ID)
    assert(*all_collections[0].collection_id == 1, 'Wrong first collection ID');

    // Create another collection
    let name = "Second Collection";
    let symbol = "TEST2";
    let collection_details: ByteArray = "Second test collection";

    start_cheat_caller_address(factory_address, artist);
    factory_dispatcher.create_collection(artist, name, symbol, collection_details);
    stop_cheat_caller_address(factory_address);

    // Verify the collection was added
    let updated_collections = factory_dispatcher.get_all_collections();
    assert(updated_collections.len() == 2, 'Collection not added');
}


#[test]
fn test_mint_pass() {
    let factory_address = deploy_factory_contract();
    let erc20_address = deploy_erc20_contract();

    let pauser = contract_address_const::<'pauser'>();
    let name = "TestCollection";
    let symbol = "TEST";

    let collection_details: ByteArray = "Test collection description";

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    start_cheat_caller_address(factory_address, pauser);
    let tribes_nft_address = factory_dispatcher
        .create_collection(pauser, name, symbol, collection_details);
    stop_cheat_caller_address(factory_address);

    let token_idispatcher = IExternalDispatcher { contract_address: erc20_address };
    token_idispatcher.mint(pauser, 20000);

    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_address };

    start_cheat_caller_address(erc20_address, pauser);
    erc20_dispatcher.approve(tribes_nft_address, 1000);
    stop_cheat_caller_address(erc20_address);

    let nft_dispatcher = IERC721Dispatcher { contract_address: tribes_nft_address };

    start_cheat_caller_address(tribes_nft_address, pauser);
    nft_dispatcher.whitelist_address(pauser);

    nft_dispatcher.set_subscription_fee(20);

    let token_id = nft_dispatcher.mint_ticket_nft(20, erc20_address);
    stop_cheat_caller_address(tribes_nft_address);

    let contract_balance = erc20_dispatcher.balance_of(tribes_nft_address);
    assert(contract_balance == 16, 'Artist bal ereror');

    let factory_balance = erc20_dispatcher.balance_of(factory_address);
    assert(factory_balance == 4, 'factory bal ereror');

    let owner = nft_dispatcher.owner(pauser, token_id);

    assert(owner, 'Nft owner error');
}

#[test]
#[should_panic(expected: 'symbol taken')]
fn test_symbol_should_panic() {
    // Setup
    let factory_address = deploy_factory_contract();
    let erc20_address = deploy_erc20_contract();
    let owner = contract_address_const::<'owner'>();
    let artist = contract_address_const::<'pauser'>();

    let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

    // Add payment token
    start_cheat_caller_address(factory_address, owner);

    // Create first collection
    let name = "TestCollection";
    let symbol = "TEST";
    let duration: u64 = 1746461445 + 86400;
    let collection_details: ByteArray = "Test collection description";

    start_cheat_caller_address(factory_address, artist);
    factory_dispatcher
        .create_collection(artist, name.clone(), symbol.clone(), collection_details.clone());

    // Try creating another collection with the same symbol (should fail)
    let name2: ByteArray = "SecondCollection";
    factory_dispatcher
        .create_collection(
            artist, name2.clone(), symbol.clone(), // Same symbol
            collection_details.clone(),
        );
    stop_cheat_caller_address(factory_address);
}
// #[test]
// #[should_panic(expected: 'Not Whitelisted')]
// fn test_mint_pass_without_been_whitelisted() {
//     let pauser = contract_address_const::<'pauser'>();
//     let user = contract_address_const::<'user'>();
//     let owner = contract_address_const::<'owner'>();
//     let name = "TestCollection";
//     let symbol = "TEST";
//     let collection_details: ByteArray = "Test collection description";

//     let factory_address = deploy_factory_contract();
//     let erc20_address = deploy_erc20_contract();
//     start_cheat_caller_address(factory_address, owner);

//     let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

//     start_cheat_caller_address(factory_address, pauser);
//     let tribes_nft_address = factory_dispatcher
//         .create_collection(pauser, name, symbol, collection_details);
//     let trybe_nft = IERC721Dispatcher { contract_address: tribes_nft_address };
//     trybe_nft.mint_ticket_nft(20);

//     stop_cheat_caller_address(factory_address);
// }

// #[test]
// #[should_panic(expected: 'Pausable: paused')]
// fn test_mint_pass_when_paused() {
//     let pauser = contract_address_const::<'pauser'>();
//     let user = contract_address_const::<'user'>();
//     let owner = contract_address_const::<'owner'>();
//     let name = "TestCollection";
//     let symbol = "TEST";

//     let collection_details: ByteArray = "Test collection description";

//     let (factory_address, erc20_address) = deploy_factory_contract();

//     start_cheat_caller_address(factory_address, owner);
//     let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

//     start_cheat_caller_address(factory_address, pauser);
//     let tribes_nft_address = factory_dispatcher
//         .create_collection(pauser, name, symbol, collection_details);
//     stop_cheat_caller_address(factory_address);

//     let nft_dispatcher = IERC721Dispatcher { contract_address: tribes_nft_address };
//     let protocol_vault = contract_address_const::<'owner'>();
//     start_cheat_caller_address(tribes_nft_address, protocol_vault);
//     nft_dispatcher.whitelist_address(user);
//     nft_dispatcher.pause();
//     nft_dispatcher.mint_ticket_nft(user);
//     stop_cheat_caller_address(tribes_nft_address);
// }

// #[test]
// fn test_mint_pass_when_unpaused() {
//     let pauser = contract_address_const::<'pauser'>();
//     let user = contract_address_const::<'user'>();
//     let owner = contract_address_const::<'owner'>();
//     let name = "TestCollection";
//     let symbol = "TEST";
//     let duration: u64 = 1746461445 + 86400;
//     let grace_period: u64 = duration + 3600;
//     let passcost: u256 = 10000_u256;
//     let payment_address = contract_address_const::<'payment_address'>();
//     let collection_details: ByteArray = "Test collection description";

//     let factory_address = deploy_factory_contract();
//     let erc20_address = deploy_erc20_contract();

//     let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_address };

//     start_cheat_caller_address(factory_address, owner);

//     start_cheat_caller_address(erc20_address, pauser);

//     erc20_dispatcher.mint(pauser, 2000);
//     token_dispatcher.approve(contract_address, 1000);
//     stop_cheat_caller_address(erc20_address);
//     let factory_dispatcher = ITribesFactoryDispatcher { contract_address: factory_address };

//     start_cheat_caller_address(factory_address, pauser);
//     let tribes_nft_address = factory_dispatcher
//         .create_collection(pauser, name, symbol, collection_details);
//     stop_cheat_caller_address(factory_address);

//     let nft_dispatcher = IERC721Dispatcher { contract_address: tribes_nft_address };
//     let protocol_vault = contract_address_const::<'owner'>();
//     start_cheat_caller_address(tribes_nft_address, protocol_vault);
//     nft_dispatcher.whitelist_address(user);

//     nft_dispatcher.pause();
//     nft_dispatcher.unpause();

//     nft_dispatcher.mint_ticket_nft(user);
//     stop_cheat_caller_address(tribes_nft_address);
// }


