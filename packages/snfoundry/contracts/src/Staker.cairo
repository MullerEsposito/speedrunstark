use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    // Core functions
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    // Getters
    fn balances(self: @T, account: ContractAddress) -> u256;
    fn completed(self: @T) -> bool;
    fn deadline(self: @T) -> u64;
    fn example_external_contract(self: @T) -> ContractAddress;
    fn open_for_withdraw(self: @T) -> bool;
    fn eth_token_dispatcher(self: @T) -> IERC20CamelDispatcher;
    fn threshold(self: @T) -> u256;
    fn total_balance(self: @T) -> u256;
    fn time_left(self: @T) -> u64;
}

#[starknet::contract]
pub mod Staker {
    use contracts::ExampleExternalContract::{
        IExampleExternalContractDispatcher, IExampleExternalContractDispatcherTrait,
    };
    use starknet::storage::Map;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use super::{ContractAddress, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IStaker};

    const THRESHOLD: u256 = 1000000000000000000; // ONE_ETH_IN_WEI: 10 ^ 18;
    const ONE_DAY: u64 = 86400;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Stake: Stake,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
        #[key]
        sender: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        eth_token_dispatcher: IERC20CamelDispatcher,
        balances: Map<ContractAddress, u256>,
        deadline: u64,
        open_for_withdraw: bool,
        external_contract_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        eth_contract: ContractAddress,
        external_contract_address: ContractAddress,
    ) {
        self.eth_token_dispatcher.write(IERC20CamelDispatcher { contract_address: eth_contract });
        self.external_contract_address.write(external_contract_address);
        self.deadline.write(get_block_timestamp() + (ONE_DAY * 3));
        self.open_for_withdraw.write(false);
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        fn stake(ref self: ContractState, amount: u256) {
            self.not_completed();
            assert!(self.get_current_time() < self.deadline(), "Staking period has ended");

            let sender: ContractAddress = get_caller_address();
            self.balances.write(sender, self.balances(sender) + amount);
            self.balances.write(get_contract_address(), self.total_balance() + amount);            
            self.eth_token_dispatcher().transferFrom(sender, get_contract_address(), amount);

            self.emit(Stake { sender, amount });
        }

        fn execute(ref self: ContractState) {
            self.not_completed();

            assert!(self.get_current_time() >= self.deadline(), "Staking period has not ended");
            
            if self.total_balance() >= self.threshold() {                
                self.complete_transfer(self.total_balance());
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        fn withdraw(ref self: ContractState) {
            self.not_completed();

            assert!(self.open_for_withdraw(), "Withdraw is not open");
            
            let sender: ContractAddress = get_caller_address();

            assert!(self.balances(sender) > 0, "No balance to withdraw");

            assert!(self.total_balance() >= self.balances(sender), "Insufficient contract balance");

            self.eth_token_dispatcher().transfer(sender, self.balances(sender));
            self.balances.write(sender, 0);
            self.balances.write(get_contract_address(), self.total_balance() - self.balances(sender));
        }

        fn balances(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_balance(self: @ContractState) -> u256 {
            self.balances.read(get_contract_address())
        }

        fn deadline(self: @ContractState) -> u64 {
            self.deadline.read()
        }

        fn threshold(self: @ContractState) -> u256 {
            THRESHOLD
        }

        fn eth_token_dispatcher(self: @ContractState) -> IERC20CamelDispatcher {
            self.eth_token_dispatcher.read()
        }

        fn open_for_withdraw(self: @ContractState) -> bool {
            self.open_for_withdraw.read()
        }

        fn example_external_contract(self: @ContractState) -> ContractAddress {
            self.external_contract_address.read()
        }

        fn completed(self: @ContractState) -> bool {
            let external_contract_dispatcher: IExampleExternalContractDispatcher = IExampleExternalContractDispatcher { contract_address: self.example_external_contract() };
            
            return external_contract_dispatcher.completed();
        }
        
        fn time_left(self: @ContractState) -> u64 {
            let current_time: u64 = get_block_timestamp();
            let deadline: u64 = self.deadline.read();

            if current_time >= deadline {
                return 0;
            }

            return deadline - current_time;
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn complete_transfer(ref self: ContractState, amount: u256) { 
            let external_contract_dispatcher: IExampleExternalContractDispatcher = IExampleExternalContractDispatcher { contract_address: self.example_external_contract() };
                       
            assert!(amount <= self.total_balance(), "Insufficient balance to transfer");
            self.eth_token_dispatcher().transfer(self.example_external_contract(), amount);
            self.balances.write(get_contract_address(), 0);
            external_contract_dispatcher.complete();
        }
        
        fn not_completed(ref self: ContractState) {
            let external_contract_dispatcher: IExampleExternalContractDispatcher = IExampleExternalContractDispatcher { contract_address: self.example_external_contract() };
            assert!(!external_contract_dispatcher.completed(), "External contract is already completed");
        }

        fn get_current_time(self: @ContractState) -> u64 {
            get_block_timestamp()
        }
    }
}
