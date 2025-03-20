#[starknet::contract]
pub mod TribesNftFactory {
    use loop_starknet::interfaces::ITribesFactory;
    use core::traits::{TryInto, Into};
    use core::serde::Serde;
    use core::num::traits::Zero;

    use openzeppelin_token::erc20::{ ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use OwnableComponent::InternalTrait;

    use starknet::{
        ContractAddress, class_hash::ClassHash, syscalls::deploy_syscall, SyscallResultTrait,
        get_block_timestamp, get_contract_address,
        storage::{
            Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess, Vec,
            VecTrait, MutableVecTrait
        }
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        vault_classhash: ClassHash,
        tribes_nft_classhash: ClassHash,
        house_percentage: u32,
        collection_count: u32,
        protocol_vault: ContractAddress,
        collections: Vec<Collection>,
        id_to_collections: Map<u32, Collection>,
        artist_collections: Map<ContractAddress, Vec<Collection>>,
        symbol_available: Map<ByteArray, bool>,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[derive(Clone, Drop, Serde, starknet::Store)]
    pub struct Collection {
        collection_id: u32,
        name: ByteArray,
        symbol: ByteArray,
        artist: ContractAddress,
        address: ContractAddress,
        created_at: u64,
        house_percentage: u32,
        artist_percentage: u32,
        collection_info: ByteArray
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CollectionCreated: CollectionCreated,
        RoyaltiesUpdated: RoyaltiesUpdated,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }


    #[derive(Drop, starknet::Event)]
    struct CollectionCreated {
        artist: ContractAddress,
        contract_address: ContractAddress,
        house_percentage: u32,
        artist_percentage: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct RoyaltiesUpdated {
        house_percentage: u32,
        updated_at: u64
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        protocol_vault: ContractAddress,
        house_percentage: u32,
        vault_classhash: ClassHash,
        tribes_classhash: ClassHash
    ) {
        assert(
            owner.is_non_zero(), 'invalid owner or fee_collector'
        );

        self.ownable.initializer(owner);
        self.protocol_vault.write(protocol_vault);
        self.house_percentage.write(house_percentage);
        self.vault_classhash.write(vault_classhash);
        self.tribes_nft_classhash.write(tribes_classhash);
    }

    // #[abi_embed(v0)]
    /// @notice Using pauser as artist / owner
    #[abi(embed_v0)]
    impl ITribesFactoryImpl of ITribesFactory<ContractState> {
        fn create_collection(
            ref self: ContractState,
            pauser: ContractAddress,
            name: ByteArray,
            symbol: ByteArray,
            duration: u64,
            grace_period: u64,
            pass_cost: u256,
            payment_address: ContractAddress,
            collection_details: ByteArray
        ) -> (ContractAddress, ContractAddress) {
            assert(
                pauser.is_non_zero() && payment_address.is_non_zero(),
                'invalid pauser or payment addr'
            );

            let house_percentage = self.house_percentage.read();
            let protocol_vault = self.protocol_vault.read();
            let collection_count = self.collection_count.read();
            let new_collections_count = collection_count + 1;

            let tribes_classhash = self.tribes_nft_classhash.read();
            let vault_classhash = self.vault_classhash.read();

            let artist_percentage = 100 - house_percentage;
            // let symbol_is_available = self.check_symbol_is_available(symbol.clone());
            // assert(symbol_is_available, 'symbol taken');

            let mut tribes_constructor_calldata = ArrayTrait::new();
            pauser.serialize(ref tribes_constructor_calldata);
            name.serialize(ref tribes_constructor_calldata);
            symbol.serialize(ref tribes_constructor_calldata);

            let (tribes_nft_address, _) = deploy_syscall(
                tribes_classhash, 0, tribes_constructor_calldata.span(), true
            )
                .unwrap_syscall();

            let contract = get_contract_address();
            let mut vault_constructor_calldata = ArrayTrait::new();
            new_collections_count.serialize(ref vault_constructor_calldata);
            pauser.serialize(ref vault_constructor_calldata);
            tribes_nft_address.serialize(ref vault_constructor_calldata);
            pass_cost.serialize(ref vault_constructor_calldata);
            grace_period.serialize(ref vault_constructor_calldata);
            duration.serialize(ref vault_constructor_calldata);
            payment_address.serialize(ref vault_constructor_calldata);
            house_percentage.serialize(ref vault_constructor_calldata);
            artist_percentage.serialize(ref vault_constructor_calldata);
            protocol_vault.serialize(ref vault_constructor_calldata);
            contract.serialize(ref vault_constructor_calldata);

            let (vault_address, _) = deploy_syscall(
                vault_classhash, 0, vault_constructor_calldata.span(), false
            )
                .unwrap_syscall();

            let mut collection: Collection = Collection {
                collection_id: new_collections_count,
                name,
                symbol,
                artist: pauser,
                address: tribes_nft_address,
                created_at: get_block_timestamp(),
                house_percentage,
                artist_percentage,
                collection_info: collection_details
            };

            self.collections.append().write(collection.clone());
            self.id_to_collections.entry(new_collections_count).write(collection.clone());
            self.artist_collections.entry(pauser).append().write(collection.clone());

            self.collection_count.write(new_collections_count);

            self
                .emit(
                    CollectionCreated {
                        artist: pauser,
                        contract_address: tribes_nft_address,
                        house_percentage,
                        artist_percentage,
                    }
                );

            (tribes_nft_address, vault_address)
        }

        fn update_royalties(ref self: ContractState, new_house_percentage: u32) {
            self.ownable.assert_only_owner();
            assert(new_house_percentage > 0, 'invalid percentage');
            self.house_percentage.write(new_house_percentage);
            self
                .emit(
                    RoyaltiesUpdated {
                        house_percentage: new_house_percentage, updated_at: get_block_timestamp()
                    }
                );
        }

        fn get_collection(self: @ContractState, collection_id: u32) -> Collection {
            self.id_to_collections.entry(collection_id).read()
        }

        fn get_artist_collections(
            self: @ContractState, artist: ContractAddress
        ) -> Array<Collection> {
            let mut collection_arr = ArrayTrait::new();

            let artist_collections = self.artist_collections.entry(artist);
            let mut i = 0;
            loop {
                if i >= artist_collections.len() {
                    break;
                }
                collection_arr.append(artist_collections.at(i).read());
                i += 1;
            };

            collection_arr
        }

        fn get_all_collections(self: @ContractState) -> Array<Collection> {
            let mut collections_arr = ArrayTrait::new();
            let stored_collections = self.collections;

            for i in 0
                ..stored_collections
                    .len() {
                        collections_arr.append(self.collections.at(i).read());
                    };

            collections_arr
        }

        fn withdraw( ref self: ContractState, receiver: ContractAddress, token: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert(receiver.is_non_zero(), 'invalid receiver');
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token };
            erc20_dispatcher.transfer(receiver, amount);
        }

    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait { // fn check_symbol_is_available(self: @ContractState, symbol: ByteArray) -> bool {
    // self.symbol_available.entry(symbol).read()
    // }
    }
}
