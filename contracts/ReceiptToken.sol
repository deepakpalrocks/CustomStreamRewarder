// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/ERC20.sol)
pragma solidity ^0.8.19;
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICustomStreamRewarder } from "./interfaces/ICustomStreamRewarder.sol"; 
contract ReceiptToken is ERC20 { 

    address public rewarder;
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    // should only be called by 1. camelotStaking for grail Lp deposits 2. masterCampie for other general staking token such as mGrail or CMP-ETH Lp tokens
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    // should only be called by 1. camelotStaking for grail Lp deposits 2. masterCampie for other general staking token such as mGrail or CMP-ETH Lp tokens
    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 _amount) internal override {
        if(from != address(0))
        ICustomStreamRewarder(rewarder).updateFor(from);
        if(to != address(0))
        ICustomStreamRewarder(rewarder).updateFor(to);
    }
    function setRewarder(address _rewarder) public {
        rewarder = _rewarder;
    }
}