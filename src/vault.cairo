#[starknet::contract]
pub mod Vault {
    use super::super::interfaces::IERC721;
    use starknet::storage::StoragePathEntry;
    use OwnableComponent::InternalTrait;
    use starknet::{
        ContractAddress, get_caller_address, contract_address_const, get_block_timestamp
    };
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait, MutableVecTrait
    };
    use core::{serde::Serde, num::traits::Zero};
    use openzeppelin_token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use loop_starknet::interfaces::{IVault, IERC721Dispatcher, IERC721DispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);


    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        total_subscribers: u256,
        factory_address: ContractAddress,
        protocol_vault: ContractAddress,
        payment_token: ContractAddress,
        tribe_details: Map<ContractAddress, TribeDetails>,
        user_payment_ids: Map<ContractAddress, Vec<u256>>,
        user_pass_details: Map<ContractAddress, PassDetails>,
        pass_validity_details: Map<u32, TribePassValidity>,
        artist_details: Map<ContractAddress, ArtistDetails>,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[derive(Clone, Drop, Serde, starknet::Store)]
    pub struct TribeDetails {
        tribe_id: u32,
        artist: ContractAddress,
        tribe_nft_address: ContractAddress,
        pass_cost: u256,
        pass_duration: u64,
        grace_period: u64,
        payment_address: ContractAddress,
        house_percentage: u32,
        artist_percentage: u32,
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct TribePassValidity {
        tribe_id: u32,
        is_valid: bool,
        expires_at: u64,
        grace_period: u64,
        in_grace_period: bool,
        grace_period_end: bool
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct PassDetails {
        tribe_nft_address: ContractAddress,
        token_id: u256,
        owner: ContractAddress,
        is_valid: bool,
        expires_at: u64
    }

    #[derive(Drop, Serde, starknet::Store)]
    pub struct ArtistDetails {
        artist: ContractAddress,
        total_royalties_earned: u256,
        total_passes: u64,
        active_passes: u64
    }

    #[derive(Drop, Serde)]
    pub enum PassStatus {
        Active,
        InGracePeriod,
        Expired
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PassMinted: PassMinted,
        PassRenewed: PassRenewed,
        PassBurned: PassBurned,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct PassMinted {
        owner: ContractAddress,
        token_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct PassRenewed {
        owner: ContractAddress,
        token_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct PassBurned {
        token_id: u32,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        tribe_id: u32,
        artist: ContractAddress,
        tribe_nft_address: ContractAddress,
        pass_cost: u256,
        grace_period: u64,
        pass_duration: u64,
        payment_address: ContractAddress,
        house_percentage: u32,
        artist_percentage: u32,
        payment_token: ContractAddress,
        protocol_vault: ContractAddress,
        factory: ContractAddress
    ) {
        let mut tribe_details = TribeDetails {
            tribe_id,
            artist,
            tribe_nft_address,
            pass_cost,
            pass_duration,
            grace_period,
            payment_address,
            house_percentage,
            artist_percentage
        };

        let mut artist_details = ArtistDetails {
            artist, total_royalties_earned: 0, total_passes: 0, active_passes: 0
        };

        self.ownable.initializer(artist);
        self.factory_address.write(factory);
        self.payment_token.write(payment_token);
        self.protocol_vault.write(protocol_vault);
        self.tribe_details.entry(tribe_nft_address).write(tribe_details.clone());
        self.artist_details.entry(artist).write(artist_details);
    }

    #[abi(embed_v0)]
    impl IVaultImpl of IVault<ContractState> {
        /// HIGH ALERT: You need a means to validate offchain payment
        fn mint_pass(
            ref self: ContractState,
            artist: ContractAddress,
            tribe_nft_address: ContractAddress,
            payment_id: u256
        ) {
            let caller = get_caller_address();
            let payment_token = self.payment_token.read();
            let protocol_vault = self.protocol_vault.read();
            let factory = self.factory_address.read();
            let artist_detail = self.artist_details.entry(artist).read();
            let tribe: TribeDetails = self.tribe_details.entry(tribe_nft_address).read();

            let tribe_id = tribe.tribe_id;
            let pass_duration = tribe.pass_duration;
            let pass_cost = tribe.pass_cost;
            let payment_address = tribe.payment_address;
            let artist_percentage = tribe.artist_percentage;
            let grace_period = tribe.grace_period;

            assert(tribe_id > 0, 'collection not found');

            let token_dispatcher = ERC20ABIDispatcher { contract_address: payment_token };

            let artist_royalty = self.calculate_percentage(pass_cost, artist_percentage);
            /// @notice Transfers token from protocol vault to artist 70%
            token_dispatcher.transfer_from(protocol_vault, payment_address, artist_royalty);
            /// @notice Transfers token from protocol vault to factory contract 30%
            token_dispatcher.transfer_from(protocol_vault, factory, pass_cost - artist_royalty);

            let pass_expiry = get_block_timestamp() + pass_duration;
            // let grace_period_end_time = pass_expiry + grace_period;

            let mut tribe_pass_validity = TribePassValidity {
                tribe_id,
                is_valid: true,
                expires_at: pass_expiry,
                grace_period,
                in_grace_period: false,
                grace_period_end: false
            };

            let mut pass_details = PassDetails {
                tribe_nft_address,
                token_id: tribe_id.into(),
                owner: caller,
                is_valid: true,
                expires_at: pass_expiry
            };

            let total_royalties_earned = artist_detail.total_royalties_earned + artist_royalty;
            let total_passes = artist_detail.total_passes + 1;
            let active_passes = artist_detail.active_passes + 1;
            let mut new_artist_detail = ArtistDetails {
                artist, total_royalties_earned, total_passes, active_passes
            };

            self.user_payment_ids.entry(caller).append().write(payment_id);
            self.pass_validity_details.entry(tribe_id).write(tribe_pass_validity);
            self.user_pass_details.entry(caller).write(pass_details);
            self.artist_details.entry(artist).write(new_artist_detail);

            let tribe_nft_dispatcher = IERC721Dispatcher { contract_address: tribe_nft_address };
            tribe_nft_dispatcher.mint_ticket_nft(caller, tribe_id.into());

            self.emit(PassMinted { owner: caller, token_id: tribe_id });
        }

        /// HIGH ALERT: You need a means to validate offchain payment
        fn renew_pass(
            ref self: ContractState, tribe_nft_address: ContractAddress, payment_id: u256
        ) {
            let caller = get_caller_address();
            let payment_token = self.payment_token.read();
            let protocol_vault = self.protocol_vault.read();
            let factory = self.factory_address.read();
            let pass_detail = self.user_pass_details.entry(caller).read();
            let tribe: TribeDetails = self.tribe_details.entry(tribe_nft_address).read();
            let artist = tribe.artist;
            let artist_detail = self.artist_details.entry(artist).read();

            let tribe_id = tribe.tribe_id;
            let new_pass_duration = tribe.pass_duration;
            let pass_cost = tribe.pass_cost;
            let payment_address = tribe.payment_address;
            let artist_percentage = tribe.artist_percentage;
            let grace_period = tribe.grace_period;

            assert(pass_detail.owner == caller, 'user record not found');
            assert(tribe_id > 0, 'collection not found');

            let token_dispatcher = ERC20ABIDispatcher { contract_address: payment_token };

            let artist_royalty = self.calculate_percentage(pass_cost, artist_percentage);
            /// @notice Transfers token from protocol vault to artist 70%
            token_dispatcher.transfer_from(protocol_vault, payment_address, artist_royalty);
            /// @notice Transfers token from protocol vault to factory contract 30%
            token_dispatcher.transfer_from(protocol_vault, factory, pass_cost - artist_royalty);

            let pass_validity: TribePassValidity = self.check_pass_validity(tribe_id);

            let mut new_pass_expiry = 0;
            if pass_validity.expires_at >= get_block_timestamp() {
                new_pass_expiry = get_block_timestamp() + new_pass_duration;
            } else {
                new_pass_expiry = pass_detail.expires_at + new_pass_duration;
            }

            let mut tribe_pass_validity = TribePassValidity {
                tribe_id,
                is_valid: true,
                expires_at: new_pass_expiry,
                grace_period,
                in_grace_period: false,
                grace_period_end: false
            };

            let mut pass_details = PassDetails {
                tribe_nft_address,
                token_id: tribe_id.into(),
                owner: caller,
                is_valid: true,
                expires_at: new_pass_expiry
            };

            let total_royalties_earned = artist_detail.total_royalties_earned + artist_royalty;
            let total_passes = artist_detail.total_passes + 1;
            let active_passes = artist_detail.active_passes + 1;
            let mut new_artist_detail = ArtistDetails {
                artist, total_royalties_earned, total_passes, active_passes
            };

            self.user_payment_ids.entry(caller).append().write(payment_id);
            self.pass_validity_details.entry(tribe_id).write(tribe_pass_validity);
            self.user_pass_details.entry(caller).write(pass_details);
            self.artist_details.entry(artist).write(new_artist_detail);

            self.emit(PassRenewed { owner: pass_detail.owner, token_id: tribe_id });
        }


        fn burn_expired_pass(ref self: ContractState, token_id: u32) {
            let caller = get_caller_address();
            let pass_validity = self.check_pass_validity(token_id);
            assert(pass_validity.expires_at >= get_block_timestamp(), 'pass still valid');
            assert(
                pass_validity.grace_period + pass_validity.expires_at >= get_block_timestamp(),
                'pass still in grace period'
            );

            let pass_detail = self.user_pass_details.entry(caller).read();
            let tribe_nft_dispatcher = IERC721Dispatcher {
                contract_address: pass_detail.tribe_nft_address
            };

            tribe_nft_dispatcher.burn(token_id.into());

            self.emit(PassBurned { token_id });
        }

        fn check_pass_status(self: @ContractState, token_id: u32) -> PassStatus {
            let pass_validity_detail: TribePassValidity = self
                .pass_validity_details
                .entry(token_id)
                .read();
            let pass_expiry = pass_validity_detail.expires_at;
            let grace_period = pass_validity_detail.grace_period;
            let current_time = get_block_timestamp();

            if current_time < pass_expiry {
                PassStatus::Active
            } else if current_time > pass_expiry && current_time < pass_expiry + grace_period {
                PassStatus::InGracePeriod
            } else {
                PassStatus::Expired
            }
        }


        fn check_validity(self: @ContractState, token_id: u32) -> TribePassValidity {
            self.pass_validity_details.entry(token_id).read()
        }

        fn get_artist_info(self: @ContractState, artist_address: ContractAddress) -> ArtistDetails {
            self.artist_details.entry(artist_address).read()
        }

        fn get_user_pass(self: @ContractState, user: ContractAddress) -> PassDetails {
            self.user_pass_details.entry(user).read()
        }

        fn get_tribe_info(
            self: @ContractState, tribe_nft_address: ContractAddress
        ) -> TribeDetails {
            self.tribe_details.entry(tribe_nft_address).read()
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn calculate_percentage(self: @ContractState, amount: u256, artist_perc: u32) -> u256 {
            let artist_royalty: u256 = (amount * artist_perc.into()) / 100;
            artist_royalty
        }

        fn check_pass_validity(self: @ContractState, token_id: u32) -> TribePassValidity {
            self.pass_validity_details.entry(token_id).read()
        }

        fn status(self: @ContractState) {}
    }
}
