// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.19;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * @author Tim Sigl 
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
* This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the
DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DecentralizedStableCoin__MustBeMoreThanZero();    
    error DecentralizedStableCoin__BurnAmountExceedsBalance(uint256 amount, uint256 balance);
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("Decentralized Stable Coin", "DSC") {

    }

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) revert DecentralizedStableCoin__MustBeMoreThanZero(); 
        if (amount > balanceOf(msg.sender)) revert DecentralizedStableCoin__BurnAmountExceedsBalance(amount, balanceOf(msg.sender));
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool){
        if (to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (amount <= 0) revert DecentralizedStableCoin__MustBeMoreThanZero();
        _mint(to, amount);
        return true;
    }
}
