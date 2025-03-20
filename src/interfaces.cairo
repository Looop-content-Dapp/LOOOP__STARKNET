use starknet::ContractAddress;
use loop_starknet::vault::Vault::{
    PassStatus, PassDetails, ArtistDetails, TribePassValidity, TribeDetails
};
use loop_starknet::factory::TribesNftFactory::Collection;

#[starknet::interface]
pub trait IERC721<TContractState> {
    fn burn(ref self: TContractState, token_id: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn ownerOf(self: @TContractState, token_id: u256) -> ContractAddress;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    // IERC721Metadata
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn token_uri(self: @TContractState, token_id: u256) -> felt252;
    fn mint_ticket_nft(ref self: TContractState, recipient: ContractAddress, token_id: u256);
}


#[starknet::interface]
pub trait ITribesFactory<TContractState> {
    fn create_collection(
        ref self: TContractState,
        pauser: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        duration: u64,
        grace_period: u64,
        pass_cost: u256,
        payment_address: ContractAddress,
        collection_details: ByteArray
    ) -> (ContractAddress, ContractAddress);
    fn update_royalties(ref self: TContractState, new_house_percentage: u32);
    fn withdraw( ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256);

    fn get_collection(self: @TContractState, collection_id: u32) -> Collection;
    fn get_artist_collections(self: @TContractState, artist: ContractAddress) -> Array<Collection>;
    fn get_all_collections(self: @TContractState) -> Array<Collection>;
}

#[starknet::interface]
pub trait IVault<TContractState> {
    fn renew_pass(ref self: TContractState, tribe_nft_address: ContractAddress, payment_id: u256);
    fn mint_pass(ref self: TContractState, artist: ContractAddress, tribe_nft_address: ContractAddress, payment_id: u256);
    fn burn_expired_pass(ref self: TContractState, token_id: u32);

    fn check_pass_status(self: @TContractState, token_id: u32) -> PassStatus;
    fn check_validity(self: @TContractState, token_id: u32) -> TribePassValidity;
    fn get_artist_info(self: @TContractState, artist_address: ContractAddress) -> ArtistDetails;
    fn get_user_pass(self: @TContractState, user: ContractAddress) -> PassDetails;
    fn get_tribe_info(self: @TContractState, tribe_nft_address: ContractAddress) -> TribeDetails;
}
