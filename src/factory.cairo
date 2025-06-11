#[starknet::contract]
pub mod TribesNftFactory {
    use OwnableComponent::InternalTrait;
    use core::num::traits::Zero;
    use core::serde::Serde;
    use loop_starknet::interfaces::ITribesFactory;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::class_hash::ClassHash;
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ContractAddress, SyscallResultTrait, get_caller_address, get_block_timestamp,
        get_contract_address,
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
        owner: ContractAddress,
        house_percentage: u32,
        collection_count: u32,
        collections: Vec<Collection>,
        id_to_collections: Map<u32, Collection>,
        artist_collections: Map<ContractAddress, Vec<Collection>>,
        metadata: Vec<NFTMetadata>,
        // is_metadata_taken: Map<NFTMetadata, bool>,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        payment_token: ContractAddress,
    }

    #[derive(Clone, Drop, Serde, starknet::Store)]
    pub struct NFTMetadata {
        symbol: ByteArray,
    }

    #[derive(Clone, Drop, Serde, starknet::Store)]
    pub struct Collection {
        pub collection_id: u32,
        pub name: ByteArray,
        pub symbol: ByteArray,
        pub artist: ContractAddress,
        pub address: ContractAddress,
        pub created_at: u64,
        pub house_percentage: u32,
        pub artist_percentage: u32,
        pub collection_info: ByteArray,
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
        updated_at: u64,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        house_percentage: u32,
        tribes_classhash: ClassHash,
        payment_token: ContractAddress,
    ) {
        assert(owner.is_non_zero(), 'invalid owner or fee_collector');
        self.ownable.initializer(owner);
        self.house_percentage.write(house_percentage);
        self.owner.write(owner);
        self.tribes_nft_classhash.write(tribes_classhash);
        self.payment_token.write(payment_token);
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
            collection_details: ByteArray,
        ) -> ContractAddress {
            let symbol_taken = self.check_symbol_is_taken(symbol.clone());
            assert(!symbol_taken, 'symbol taken');

            let house_percentage = self.house_percentage.read();
            let contract_address = get_contract_address();
            let caller = get_caller_address();

            let collection_count = self.collection_count.read();
            let new_collections_count = collection_count + 1;

            let tribes_classhash = self.tribes_nft_classhash.read();
            let payment_token = self.payment_token.read();
            let artist_percentage = 100 - house_percentage;
            let mut tribes_constructor_calldata = ArrayTrait::new();
            pauser.serialize(ref tribes_constructor_calldata);
            name.serialize(ref tribes_constructor_calldata);
            symbol.serialize(ref tribes_constructor_calldata);
            payment_token.serialize(ref tribes_constructor_calldata);
            contract_address.serialize(ref tribes_constructor_calldata);
            caller.serialize(ref tribes_constructor_calldata);

            let (tribes_nft_address, _) = deploy_syscall(
                tribes_classhash, 0, tribes_constructor_calldata.span(), true,
            )
                .unwrap_syscall();

            let sym = symbol.clone();
            let mut collection: Collection = Collection {
                collection_id: new_collections_count,
                name,
                symbol: sym,
                artist: pauser,
                address: tribes_nft_address,
                created_at: get_block_timestamp(),
                house_percentage,
                artist_percentage,
                collection_info: collection_details,
            };

            let mut metadata: NFTMetadata = NFTMetadata { symbol: symbol.clone() };

            self.collections.append().write(collection.clone());
            self.id_to_collections.entry(new_collections_count).write(collection.clone());
            self.artist_collections.entry(pauser).append().write(collection.clone());
            self.collection_count.write(new_collections_count);
            self.metadata.append().write(metadata);

            self
                .emit(
                    CollectionCreated {
                        artist: pauser,
                        contract_address: tribes_nft_address,
                        house_percentage,
                        artist_percentage,
                    },
                );

            tribes_nft_address
        }


        fn update_royalties(ref self: ContractState, new_house_percentage: u32) {
            self.ownable.assert_only_owner();
            assert(new_house_percentage > 0, 'invalid percentage');
            self.house_percentage.write(new_house_percentage);
            self
                .emit(
                    RoyaltiesUpdated {
                        house_percentage: new_house_percentage, updated_at: get_block_timestamp(),
                    },
                );
        }

        fn get_collection(self: @ContractState, collection_id: u32) -> Collection {
            self.id_to_collections.entry(collection_id).read()
        }

        fn get_artist_collections(
            self: @ContractState, artist: ContractAddress,
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

        fn withdraw(
            ref self: ContractState,
            token: ContractAddress,
            receiver: ContractAddress,
            amount: u256,
        ) {
            self.ownable.assert_only_owner();
            assert(receiver.is_non_zero(), 'invalid receiver');
            let erc20_dispatcher = IERC20Dispatcher { contract_address: token };
            let contract_address = get_contract_address();
            let contract_balance = erc20_dispatcher.balance_of(contract_address);
            assert(contract_balance >= amount, 'insufficient bal');
            erc20_dispatcher.transfer(receiver, amount);
        }


        fn check_balance(
            self: @ContractState, token: ContractAddress, address: ContractAddress,
        ) -> u256 {
            let erc20_dispatcher = IERC20Dispatcher { contract_address: token };

            let balance = erc20_dispatcher.balance_of(address);

            balance
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn check_symbol_is_taken(self: @ContractState, symbol: ByteArray) -> bool {
            let all_metadata = self.metadata.clone();
            let mut i = 0;
            let mut taken = false;

            while i != all_metadata.len() {
                if all_metadata.at(i).read().symbol == symbol {
                    taken = true;
                }
                i += 1;
            };

            taken
        }
    }
}
