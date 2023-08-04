// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__NotEnoughBalanceToBurn();
    error DecentralizedStableCoin__ZeroBurnQuantity();
    error DecentralizedStableCoin__ZeroMintQuantity();
    error DecentralizedStableCoin__InvalidZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 tokenAmount) public override onlyOwner {
        if (tokenAmount == 0)
            revert DecentralizedStableCoin__ZeroBurnQuantity();

        if (tokenAmount > balanceOf(msg.sender))
            revert DecentralizedStableCoin__NotEnoughBalanceToBurn();

        super.burn(tokenAmount);
    }

    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        if (to == address(0))
            revert DecentralizedStableCoin__InvalidZeroAddress();
        if (amount <= 0) revert DecentralizedStableCoin__ZeroMintQuantity();
        _mint(to, amount);
        return true;
    }
}
