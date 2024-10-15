// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC1155/IERC1155.sol";

interface IScholesCollateral is IERC1155 {
    event Deposit(address depositor, uint256 optionId, uint256 baseAmount, uint256 underlyingAmount);
    event Withdraw(address depositor, address destination, uint256 optionId, uint256 baseAmount, uint256 underlyingAmount);

    function setFriendContracts() external;
    function getId(uint256 optionId, bool isBase) external view returns (uint256);
    function deposit(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount) external;
    function withdraw(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount) external;
    function withdrawTo(uint256 optionId, address to, uint256 baseAmount, uint256 underlyingAmount) external;
    function withdrawToAsPossible(uint256 optionId, address to, uint256 baseAmount, uint256 underlyingAmount, uint256 conversionPrice) external;
    function balances(address owner, uint256 optionId) external view returns (uint256 baseBalance, uint256 underlyingBalance);
    function totalSupply(uint256 id) external view returns (uint256);
    function mintCollateral(address to, uint256 id, uint256 amount) external;
    function burnCollateral(address from, uint256 id, uint256 amount) external;
    function proxySafeTransferFrom(uint256 optionId, address from, address to, uint256 id, uint256 amount) external;
}