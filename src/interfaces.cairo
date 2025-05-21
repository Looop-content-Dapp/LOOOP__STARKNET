use starknet::ContractAddress;
use loop_starknet::vault::Vault::{
    PassStatus, PassDetails, ArtistDetails, TribePassValidity, TribeDetails
};
use loop_starknet::factory::TribesNftFactory::Collection;

#[starknet::interface]
pub trait IERC721<TContractState> {
    fn mint_ticket_nft(ref self: TContractState, recipient: ContractAddress, token_id: u256);
    fn burn_nft(ref self: TContractState, token_id: u256);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn whitelist_address(ref self: TContractState, address: ContractAddress);
    fn is_whitelisted(ref self: TContractState, address: ContractAddress) -> bool;
    fn withdraw(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    );
    fn check_balance(ref self: TContractState, token: ContractAddress,) -> u256;
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
        payment_token: ContractAddress,
        collection_details: ByteArray
    ) -> (ContractAddress, ContractAddress);
    fn add_supported_token(ref self: TContractState, token: ContractAddress);
    fn get_payment_tokens(self: @TContractState) -> Array<ContractAddress>;
    fn remove_supported_token(ref self: TContractState, token: ContractAddress);
    fn update_royalties(ref self: TContractState, new_house_percentage: u32);
    fn withdraw(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    );

    fn get_collection(self: @TContractState, collection_id: u32) -> Collection;
    fn get_artist_collections(self: @TContractState, artist: ContractAddress) -> Array<Collection>;
    fn get_all_collections(self: @TContractState) -> Array<Collection>;
}

#[starknet::interface]
pub trait IVault<TContractState> {
    fn renew_pass(ref self: TContractState, tribe_nft_address: ContractAddress);
    fn mint_pass(
        ref self: TContractState, artist: ContractAddress, tribe_nft_address: ContractAddress
    );
    fn burn_expired_pass(ref self: TContractState, token_id: u32, user: ContractAddress);

    fn check_pass_status(self: @TContractState, user: ContractAddress, token_id: u32) -> bool;
    fn get_validity(self: @TContractState, token_id: u32) -> TribePassValidity;
    fn get_artist_info(self: @TContractState, artist_address: ContractAddress) -> ArtistDetails;
    fn get_user_pass(self: @TContractState, user: ContractAddress) -> PassDetails;
    fn get_tribe_info(self: @TContractState, tribe_nft_address: ContractAddress) -> TribeDetails;
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
