#[starknet::contract]
pub mod USDC {
    // Core dependencies
    use core::num::traits::Zero;
    use loop_starknet::interfaces::IUSDCToken;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, contract_address_const, get_caller_address};

    // Storage variables
    #[storage]
    struct Storage {
        // ERC-20 standard storage
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        // USDC specific storage
        owner: ContractAddress,
        paused: bool,
        blacklisted: Map<ContractAddress, bool>,
        minters: Map<ContractAddress, bool>,
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        Mint: Mint,
        Burn: Burn,
        Blacklisted: Blacklisted,
        RemovedFromBlacklist: RemovedFromBlacklist,
        PauseToggled: PauseToggled,
        MinterConfigured: MinterConfigured,
        OwnershipTransferred: OwnershipTransferred,
    }

    // Event structs
    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Burn {
        from: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Blacklisted {
        user: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RemovedFromBlacklist {
        user: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PauseToggled {
        paused: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterConfigured {
        minter: ContractAddress,
        minter_allowed: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    // Constructor
    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress) {
        self.name.write('USD Coin');
        self.symbol.write('USDC');
        self.decimals.write(6); // USDC standard is 6 decimals
        self.owner.write(_owner);
        self.paused.write(false);
        self._mint(_owner, 1_000_000_000_000_000);
    }

    // Implementation of the IUSDCToken interface
    #[abi(embed_v0)]
    impl USDCTokenImpl of IUSDCToken<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert(!self.paused.read(), 'Contract is paused');
            let sender = get_caller_address();
            assert(!self.blacklisted.read(sender), 'Sender is blacklisted');
            assert(!self.blacklisted.read(recipient), 'Recipient is blacklisted');
            assert(!recipient.is_zero(), 'Transfer to 0 address');

            // Check sender has enough balance
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');

            // Update balances
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);

            // Emit transfer event
            self.emit(Transfer { from: sender, to: recipient, value: amount });

            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            assert(!self.blacklisted.read(caller), 'Caller is blacklisted');
            assert(!self.blacklisted.read(sender), 'Sender is blacklisted');
            assert(!self.blacklisted.read(recipient), 'Recipient is blacklisted');
            assert(!sender.is_zero(), 'Transfer from 0 address');
            assert(!recipient.is_zero(), 'Transfer to 0 address');

            // Check sender has enough balance
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');

            // Check allowance
            let caller_allowance = self.allowances.read((sender, caller));
            assert(caller_allowance >= amount, 'Insufficient allowance');

            // Update balances and allowance
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.allowances.write((sender, caller), caller_allowance - amount);

            // Emit transfer event
            self.emit(Transfer { from: sender, to: recipient, value: amount });

            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            assert(!self.blacklisted.read(caller), 'Caller is blacklisted');
            assert(!self.blacklisted.read(spender), 'Spender is blacklisted');
            assert(!spender.is_zero(), 'Approve to 0 address');

            self.allowances.write((caller, spender), amount);

            // Emit approval event
            self.emit(Approval { owner: caller, spender, value: amount });

            true
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            assert(self.minters.read(caller), 'Caller is not a minter');
            assert(!self.blacklisted.read(to), 'Recipient is blacklisted');
            assert(!to.is_zero(), 'Mint to 0 address');

            self._mint(to, amount);
        }
    }

    // Additional view functions
    #[abi(embed_v0)]
    fn get_name(self: @ContractState) -> felt252 {
        self.name.read()
    }

    #[abi(embed_v0)]
    fn get_symbol(self: @ContractState) -> felt252 {
        self.symbol.read()
    }

    #[abi(embed_v0)]
    fn get_decimals(self: @ContractState) -> u8 {
        self.decimals.read()
    }

    #[abi(embed_v0)]
    fn get_total_supply(self: @ContractState) -> u256 {
        self.total_supply.read()
    }

    #[abi(embed_v0)]
    fn get_owner(self: @ContractState) -> ContractAddress {
        self.owner.read()
    }

    #[abi(embed_v0)]
    fn is_paused(self: @ContractState) -> bool {
        self.paused.read()
    }

    #[abi(embed_v0)]
    fn is_blacklisted(self: @ContractState, account: ContractAddress) -> bool {
        self.blacklisted.read(account)
    }

    #[abi(embed_v0)]
    fn is_minter(self: @ContractState, account: ContractAddress) -> bool {
        self.minters.read(account)
    }

    // Administrative functions
    #[abi(embed_v0)]
    fn burn(ref self: ContractState, amount: u256) {
        assert(!self.paused.read(), 'Contract is paused');
        let caller = get_caller_address();
        assert(!self.blacklisted.read(caller), 'Caller is blacklisted');

        // Check caller has enough balance
        let caller_balance = self.balances.read(caller);
        assert(caller_balance >= amount, 'Insufficient balance');

        // Update total supply and caller balance
        self.total_supply.write(self.total_supply.read() - amount);
        self.balances.write(caller, caller_balance - amount);

        // Emit events
        self.emit(Transfer { from: caller, to: contract_address_const::<0>(), value: amount });
        self.emit(Burn { from: caller, amount });
    }

    #[abi(embed_v0)]
    fn blacklist(ref self: ContractState, account: ContractAddress) {
        self.only_owner();
        assert(!account.is_zero(), 'Cannot blacklist 0 address');
        self.blacklisted.write(account, true);
        self.emit(Blacklisted { user: account });
    }

    #[abi(embed_v0)]
    fn unblacklist(ref self: ContractState, account: ContractAddress) {
        self.only_owner();
        self.blacklisted.write(account, false);
        self.emit(RemovedFromBlacklist { user: account });
    }

    #[abi(embed_v0)]
    fn pause(ref self: ContractState) {
        self.only_owner();
        self.paused.write(true);
        self.emit(PauseToggled { paused: true });
    }

    #[abi(embed_v0)]
    fn unpause(ref self: ContractState) {
        self.only_owner();
        self.paused.write(false);
        self.emit(PauseToggled { paused: false });
    }

    #[abi(embed_v0)]
    fn configure_minter(ref self: ContractState, minter: ContractAddress, minter_allowed: bool) {
        self.only_owner();
        assert(!minter.is_zero(), 'Cannot configure 0 address');
        self.minters.write(minter, minter_allowed);
        self.emit(MinterConfigured { minter, minter_allowed });
    }

    #[abi(embed_v0)]
    fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
        self.only_owner();
        assert(!new_owner.is_zero(), 'New owner is 0 address');
        let previous_owner = self.owner.read();
        self.owner.write(new_owner);
        self.emit(OwnershipTransferred { previous_owner, new_owner });
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalTrait {
        fn only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Caller is not the owner');
        }

        fn _mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Update total supply and recipient balance
            let new_total_supply = self.total_supply.read() + amount;
            self.total_supply.write(new_total_supply);
            self.balances.write(to, self.balances.read(to) + amount);

            // Emit events
            self.emit(Transfer { from: contract_address_const::<0>(), to, value: amount });
            self.emit(Mint { to, amount });
        }
    }
}
