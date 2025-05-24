use starknet::ContractAddress;
// use loop_starknet::vault::Vault::{
//     PassStatus, PassDetails, ArtistDetails, TribePassValidity, TribeDetails
// };
use loop_starknet::factory::TribesNftFactory::Collection;

#[starknet::interface]
pub trait IERC721<TContractState> {
    fn mint_ticket_nft(ref self: TContractState, recipient: ContractAddress) -> u256;
    fn burn_nft(ref self: TContractState, token_id: u256);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn whitelist_address(ref self: TContractState, address: ContractAddress);
    fn is_whitelisted(self: @TContractState, address: ContractAddress) -> bool;
    fn withdraw(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    );
    fn check_balance(self: @TContractState, token: ContractAddress,) -> u256;
    fn has_expired(ref self: TContractState, token_id: u256) -> bool;
    fn pass_expiry_date(self: @TContractState, token_id: u256) -> u64;
}


#[starknet::interface]
pub trait ITribesFactory<TContractState> {
    fn create_collection(
        ref self: TContractState,
        pauser: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        collection_details: ByteArray
    ) -> ContractAddress;
    fn update_royalties(ref self: TContractState, new_house_percentage: u32);
    fn withdraw(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    );

    fn get_collection(self: @TContractState, collection_id: u32) -> Collection;
    fn get_artist_collections(self: @TContractState, artist: ContractAddress) -> Array<Collection>;
    fn get_all_collections(self: @TContractState) -> Array<Collection>;
}


#[starknet::interface]
pub trait IUSDCToken<TContractState> {
    /// Returns the balance of the specified account
    /// # Arguments
    /// * `account` - The account to check the balance of
    /// # Returns
    /// * The balance of the account
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;

    /// Returns the allowance granted by the owner to the spender
    /// # Arguments
    /// * `owner` - The account that granted the allowance
    /// * `spender` - The account that received the allowance
    /// # Returns
    /// * The amount of allowance granted
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;

    /// Transfers tokens from the caller to the recipient
    /// # Arguments
    /// * `recipient` - The address to transfer tokens to
    /// * `amount` - The amount of tokens to transfer
    /// # Returns
    /// * `bool` - True if the transfer was successful
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;

    /// Transfers tokens from one address to another using an allowance
    /// # Arguments
    /// * `sender` - The address to transfer tokens from
    /// * `recipient` - The address to transfer tokens to
    /// * `amount` - The amount of tokens to transfer
    /// # Returns
    /// * `bool` - True if the transfer was successful
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    /// Approves a spender to withdraw tokens from the caller's account
    /// # Arguments
    /// * `spender` - The address allowed to spend the tokens
    /// * `amount` - The amount of tokens to allow the spender to withdraw
    /// # Returns
    /// * `bool` - True if the approval was successful
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;

    /// Mints new tokens to the specified address
    /// # Arguments
    /// * `to` - The address to mint tokens to
    /// * `amount` - The amount of tokens to mint
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}
