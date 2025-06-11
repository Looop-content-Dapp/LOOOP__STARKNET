const PAUSER_ROLE: felt252 = selector!("PAUSER_ROLE");
const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");

#[starknet::contract] // use loop_starknet::vault::Vault::{
//     PassStatus, PassDetails, ArtistDetails, TribePassValidity, TribeDetails
// };
pub mod TribesNFT {
    use core::num::traits::Zero;
    use loop_starknet::interfaces::IERC721;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use super::{MINTER_ROLE, PAUSER_ROLE};

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
        subscription_amount: u256,
        payment_token: ContractAddress,
        treasury: ContractAddress,
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
        PassMinted: PassMinted,
        PassBurned: PassBurned,
        Message: Message,
    }

    #[derive(Drop, starknet::Event)]
    struct Message {
        message: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct PassMinted {
        owner: ContractAddress,
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PassBurned {
        token_id: u256,
    }
    #[constructor]
    fn constructor(
        ref self: ContractState,
        pauser: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        payment_token: ContractAddress,
        treasury: ContractAddress,
        caller: ContractAddress,
    ) {
        self.erc721.initializer(name, symbol, "");
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(PAUSER_ROLE, pauser);
        self.authorized_address.write(caller);
        self.subscription_amount.write(20);
        self.payment_token.write(payment_token);
        self.treasury.write(treasury);
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
            let authorized_address = self.authorized_address.read();
            let caller = get_caller_address();
            let address = self.erc721.ownerOf(token_id);
            assert((caller == authorized_address) || (caller == address), 'Unauthorized to burn');
            self.remove_from_whitelist(address);
            self.erc721.update(Zero::zero(), token_id, get_caller_address());
            self.emit(PassBurned { token_id });
        }

        fn pass_expiry_date(self: @ContractState, token_id: u256) -> u64 {
            let expiry_date = self.expiry_date.read(token_id);
            expiry_date
        }

        fn has_expired(ref self: ContractState, token_id: u256) -> bool {
            let timestamp = get_block_timestamp();
            let expiry_date = self.expiry_date.read(token_id);
            let expired: bool = (timestamp > expiry_date);
            if (expired) {
                self.burn_nft(token_id);
            }
            expired
        }

        fn mint_ticket_nft(
            ref self: ContractState, payment_amount: u256, payment_token: ContractAddress
        ) -> u256 {
            let artist_address = get_contract_address();
            let caller = get_caller_address();
            let is_whitelisted = self.whitelist.read(caller);
            let timestamp = get_block_timestamp();
            let thirty_days = 2592000;
            let expiry_date = timestamp + thirty_days;
            // let payment_token = self.payment_token.read();
            assert(is_whitelisted, 'Not Whitelisted');
            let balance = self.erc721.balance_of(caller);
            assert(balance.is_zero(), 'ALREADY_MINTED');

            // assert(payment_token.is_non_zero(), 'Invalid payment token');
            assert(payment_amount > 0, 'Invalid payment amount');
            assert(artist_address.is_non_zero(), 'Invalid artist address');
            let subscription_amount = self.subscription_amount.read();
            assert(subscription_amount == payment_amount, 'Invalid fee');

            // let erc20_dispatcher = ERC20ABIDispatcher { contract_address: payment_token };
            let erc20_dispatcher = IERC20Dispatcher { contract_address: payment_token };

            let contract_address = get_contract_address();

            // let user_balance = erc20_dispatcher.balance_of(caller);
            // assert(user_balance >= payment_amount, 'Insufficient balance');

            let transfer_success = erc20_dispatcher
                .transfer_from(caller, contract_address, payment_amount);
            assert(transfer_success, 'Payment transfer faield');

            // Distributing payment (from contract, not caller)
            let (artist_share, treasury_share) = self.calculate_fee(payment_amount);
            let treasury_address = self.treasury.read();

            let artist_transfer = erc20_dispatcher.transfer(artist_address, artist_share);
            assert(artist_transfer, 'Artist payment failed');

            let treasury_transfer = erc20_dispatcher.transfer(treasury_address, treasury_share);
            assert(treasury_transfer, 'Treasury payment failed');

            // self.whitelist.write(caller, false); // Optional, only if re-whitelisting

            let token_id = self.next_token_id.read();

            self._mint(caller, token_id);
            self.expiry_date.write(token_id, expiry_date);
            self.next_token_id.write(token_id + 1);
            self.emit(PassMinted { owner: caller, token_id: token_id });
            token_id
        }


        fn pause(ref self: ContractState) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            self.pause.write(true);
            self.pausable.pause();
            self.emit(Message { message: 'Paused' });
        }


        fn unpause(ref self: ContractState) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            self.pause.write(false);
            self.pausable.unpause();
            self.emit(Message { message: 'unPaused' });
        }

        fn whitelist_address(ref self: ContractState, address: ContractAddress) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            let is_whitelisted = self.whitelist.read(address);
            assert(!is_whitelisted, 'Already Whitelisted');
            self.whitelist.write(address, true);
            self.emit(Message { message: 'Whitelisted' });
        }

        fn remove_from_whitelist(ref self: ContractState, address: ContractAddress) {
            let caller = get_caller_address();
            let authorized_address = self.authorized_address.read();
            assert(caller == authorized_address, 'User Not Authorized');
            self.whitelist.write(address, false);
            self.emit(Message { message: 'Whitelist Removed' });
        }

        fn is_whitelisted(self: @ContractState, address: ContractAddress) -> bool {
            let is_whitelisted = self.whitelist.read(address);
            is_whitelisted
        }

        fn withdraw(
            ref self: ContractState,
            receiver: ContractAddress,
            token: ContractAddress,
            amount: u256,
        ) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            let paused: bool = self.pause.read();
            assert(!paused, 'withdrawal paused');
            assert(receiver.is_non_zero(), 'invalid receiver');
            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token };
            assert(
                amount >= erc20_dispatcher.balance_of(get_contract_address()), 'insufficient bal',
            );
            erc20_dispatcher.transfer(receiver, amount);
            self.emit(Message { message: 'Withdraw Successful' });
        }

        fn check_balance(self: @ContractState, token: ContractAddress) -> u256 {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);

            let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token };
            let balance = erc20_dispatcher.balance_of(get_contract_address());
            balance
        }

        fn calculate_fee(self: @ContractState, payment_amount: u256) -> (u256, u256) {
            let artist_percentage: u256 = 80;

            let artist_share = (payment_amount * artist_percentage) / 100;
            let treasury_share = payment_amount - artist_share;
            (artist_share, treasury_share)
        }

        fn owner(self: @ContractState, address: ContractAddress, token_id: u256) -> bool {
            let owner = self.erc721.owner_of(token_id);
            let success = owner == address;
            success
        }
    }

    // Additional functions not part of the IERC721 interface
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn _mint(ref self: ContractState, recipient: ContractAddress, token_id: u256) {
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

