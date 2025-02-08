// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title Decentralized Stable Coin
 * @dev A decentralized alorithmic stable coin that is pegged to the US Dollar
 * @author Lovish Badlani
 * Collateral: ETH & BTC (Exogenous)
 * Relative Stable: Pegged to the US Dollar
 * Decentralized: Governed by a Algo(not DAO, not centralized entity)
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DecentralizedStableCoin__NotZeroAddress();
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();


    constructor() ERC20("Decentralized Stable Coin", "DSC") Ownable(msg.sender) {}

    /*
     * @dev Mint new tokens
     * function allows to mint tokens directly to users' wallets without first minting to owner and then transferring
     * @param _to The address to which the minted tokens will be sent
     * @param _amount The amount of tokens to mint
     * @return A boolean that indicates if the operation was successful
    */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if(_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if(_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    /*
     * @dev Burn tokens
     * @param _amount The amount of tokens to burn
    */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if(balance<_amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount); //calling super call burn function
    }

}