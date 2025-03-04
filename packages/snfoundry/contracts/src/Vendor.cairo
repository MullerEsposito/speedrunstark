use starknet::ContractAddress;
#[starknet::interface]
pub trait IVendor<T> {
    fn buy_tokens(ref self: T, eth_amount_wei: u256);
    fn withdraw(ref self: T);
    fn sell_tokens(ref self: T, amount_tokens: u256);
    fn tokens_per_eth(self: @T) -> u256;
    fn your_token(self: @T) -> ContractAddress;
    fn eth_token(self: @T) -> ContractAddress;
}

#[starknet::contract]
mod Vendor {
    use contracts::YourToken::{IYourTokenDispatcher, IYourTokenDispatcherTrait};
    use core::traits::TryInto;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_access::ownable::interface::IOwnable;
    use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use starknet::{get_caller_address, get_contract_address};
    use super::{ContractAddress, IVendor};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // ToDo Checkpoint 2: Define const TokensPerEth
    const TokensPerEth: u256 = 100;

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        eth_token: IERC20CamelDispatcher,
        your_token: IYourTokenDispatcher,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        BuyTokens: BuyTokens,
        SellTokens: SellTokens,
    }

    #[derive(Drop, starknet::Event)]
    struct BuyTokens {
        buyer: ContractAddress,
        eth_amount: u256,
        tokens_amount: u256,
    }

    //  ToDo Checkpoint 3: Define the event SellTokens
    #[derive(Drop, starknet::Event)]
    struct SellTokens {
        seller: ContractAddress,
        eth_amount: u256,
        tokens_amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        eth_token_address: ContractAddress,
        your_token_address: ContractAddress,
        owner: ContractAddress,
    ) {
        self.eth_token.write(IERC20CamelDispatcher { contract_address: eth_token_address });
        self.your_token.write(IYourTokenDispatcher { contract_address: your_token_address });
        self.ownable.initializer(owner);
    }
    #[abi(embed_v0)]
    impl VendorImpl of IVendor<ContractState> {
        fn buy_tokens(
            ref self: ContractState, eth_amount_wei: u256,
        ) { 
            let tokens_amount = eth_amount_wei * self.tokens_per_eth();
            assert!(self.your_token.read().balance_of(get_contract_address()) >= tokens_amount);
            self.eth_token.read().transferFrom(
                get_caller_address(),
                get_contract_address(),
                eth_amount_wei,
            );
            self.your_token.read().transfer(
                get_caller_address(),
                tokens_amount
            );
            Event::BuyTokens(BuyTokens {
                buyer: get_caller_address(),
                eth_amount: eth_amount_wei,
                tokens_amount,
            });
        }

        fn withdraw(ref self: ContractState) {
            assert!(self.owner() == get_caller_address());
            self.your_token.read().transfer(
                self.owner(),
                self.your_token.read().balance_of(get_contract_address())
            );
        }

        // ToDo Checkpoint 3: Implement your function sell_tokens here.
        fn sell_tokens(ref self: ContractState, amount_tokens: u256) {
            let seller_balance = self.your_token.read().balance_of(get_caller_address());
            assert!(seller_balance >= amount_tokens);
            let eth_amount = amount_tokens / self.tokens_per_eth();
            self.your_token.read().transfer_from(
                get_caller_address(),
                get_contract_address(),
                amount_tokens
            );
            self.eth_token.read().transfer(
                get_caller_address(),
                eth_amount
            );
            Event::SellTokens(SellTokens { 
                seller: get_caller_address(),
                eth_amount,
                tokens_amount: amount_tokens,
            });
        }

        fn tokens_per_eth(self: @ContractState) -> u256 {
            TokensPerEth
        }

        fn your_token(self: @ContractState) -> ContractAddress {
            self.your_token.read().contract_address
        }

        fn eth_token(self: @ContractState) -> ContractAddress {
            self.eth_token.read().contract_address
        }
    }
}
