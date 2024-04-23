// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
//import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract StSCH is ERC20 {
    address public owner;

    constructor (string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Unauthorized");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "Unauthorized");
        _burn(from, amount);
    }
}