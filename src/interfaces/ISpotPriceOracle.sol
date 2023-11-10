// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ISpotPriceOracle {
    function setMockPrice(uint256 price) external; // DANGEROUS!!! WARNING - Use only for testing! Remove before mainnet deployment.

    function spotToken() external view returns (IERC20Metadata);
    function baseToken() external view returns (IERC20Metadata);
    function isInverse() external view returns (bool);

    function description() external view returns (string memory);
    function getPrice() external view returns (uint256);
    function decimals() external view returns (uint8);
    function getTokens() external view returns (IERC20Metadata base, IERC20Metadata spot);
    function toSpot(uint256 baseAmount, uint256 price) external view returns (uint256);
    function toSpot(uint256 baseAmount) external view returns (uint256);
    function toBase(uint256 spotAmount, uint256 price) external view returns (uint256);
    function toBase(uint256 spotAmount) external view returns (uint256);
    function toBaseFromOption(uint256 optionAmount, uint256 price) external view returns (uint256);
    function toOptionFromBase(uint256 baseAmount, uint256 price) external view returns (uint256);
}