// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../types/TOptionParams.sol";
import "../types/TCollateralRequirements.sol";
import "../interfaces/IScholesOption.sol";
import "../interfaces/IOrderBook.sol";

interface IOrderBookList {
    function getLength() external view returns (uint256);
    function getOrderBook(uint256 index) external view returns (IOrderBook);
    function createScholesOptionPair(TOptionParams memory optionParams, TCollateralRequirements memory collateralReqShort) external;
}