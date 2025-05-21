const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");

#[starknet::contract]
pub mod TribesNFT {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use super::{PAUSER_ROLE, MINTER_ROLE};
    use loop_starknet::interfaces::IERC721;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlCamelImpl =
        AccessControlComponent::AccessControlCamelImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        next_token_id: u256,
        authorized_address: ContractAddress,
        whitelist: Map<ContractAddress, bool>,
        expiry_date: Map<u256, u64>,
        pause: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        pauser: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        authorized_address: ContractAddress,
    ) {
        self.erc721.initializer(name, symbol, "");
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(PAUSER_ROLE, pauser);
        self.authorized_address.write(authorized_address);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let contract_state = ERC721Component::HasComponent::get_contract(@self);
            contract_state.pausable.assert_not_paused();
        }

        fn after_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {}
    }

    // Implement the IERC721 interface
    #[abi(embed_v0)]
    impl IERC721Impl of IERC721<ContractState> {
        fn burn_nft(ref self: ContractState, token_id: u256) {
            let owner = self.erc721.ownerOf(token_id);
            self.whitelist.write(owner, false);
            self.erc721.update(Zero::zero(), token_id, get_caller_address());
        }

        fn has_expired(ref self: ContractState, token_uri: u256) -> bool {
            let timestamp = get_block_timestamp();
            let expiry_date = self.expiry_date.read(token_uri);
            let expired: bool = (timestamp > expiry_date);
            expired
        }

        fn mint_ticket_nft(ref self: ContractState, recipient: ContractAddress, token_id: u256) {
            let is_whitelisted = self.whitelist.read(recipient);
            let timestamp = get_block_timestamp();
            let thirty_days = 2592000;
            let expiry_date = timestamp + thirty_days;
            assert(is_whitelisted, 'Not Whitelisted');
            let balance = self.erc721.balance_of(recipient);
            assert(balance.is_zero(), 'ALREADY_MINTED');

            self._mint(recipient, token_id);
            self.expiry_date.write(token_id, expiry_date);
        }

        fn pause(ref self: ContractState) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            self.pause.write(true);
            self.pausable.pause();
        }


        fn unpause(ref self: ContractState) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            self.pause.write(false);
            self.pausable.unpause();
        }

        fn whitelist_address(ref self: ContractState, address: ContractAddress) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            let is_whitelisted = self.whitelist.read(address);
            assert(!is_whitelisted, 'Already Whitelisted');
            self.whitelist.write(address, true);
        }

        fn is_whitelisted(ref self: ContractState, address: ContractAddress) -> bool {
            let is_whitelisted = self.whitelist.read(address);
            is_whitelisted
        }

        fn withdraw(
            ref self: ContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
        ) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            let paused: bool = self.pause.read();
            assert(!paused, 'withdrawal paused');
            assert(receiver.is_non_zero(), 'invalid receiver');
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token };
            assert(
                amount >= erc20_dispatcher.balance_of(get_contract_address()), 'insufficient bal'
            );
            erc20_dispatcher.transfer(receiver, amount);
        }

        fn check_balance(ref self: ContractState, token: ContractAddress,) -> u256 {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);

            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token };
            let balance = erc20_dispatcher.balance_of(get_contract_address());
            balance
        }
    }

    // Additional functions not part of the IERC721 interface
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        // #[external(v0)]
        // fn pause(ref self: ContractState) {
        //     self.accesscontrol.assert_only_role(PAUSER_ROLE);
        //     self.pausable.pause();
        // }

        // #[external(v0)]
        // fn unpause(ref self: ContractState) {
        // self.accesscontrol.assert_only_role(PAUSER_ROLE);
        //     self.pausable.unpause();
        // }

        #[external(v0)]
        fn _mint(ref self: ContractState, recipient: ContractAddress, token_id: u256,) {
            // self.accesscontrol.assert_only_role(MINTER_ROLE);
            self.erc721.mint(recipient, token_id);
        }

        #[external(v0)]
        fn safe_mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            self.accesscontrol.assert_only_role(MINTER_ROLE);
            self.erc721.safe_mint(recipient, token_id, data);
        }
    }
}
