// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155.sol";

import "../types/TOptionParams.sol";
import "../types/TCollateralRequirements.sol";

import "./IScholesCollateral.sol";
import "./ISpotPriceOracle.sol";
import "./ISpotPriceOracleApprovedList.sol";
import "./IOrderBookList.sol";
import "./ITimeOracle.sol";

interface IScholesLiquidator {
    event Liquidate(uint256 indexed id, address indexed holder, address indexed liquidator);

    function setFriendContracts() external;
    function estimateLiqudationPenalty(address holder, uint256 id) external view returns (uint256 penalty, uint256 collectable);
    function liquidate(address holder, uint256 id, IOrderBook ob, TTakerEntry[] memory makers) external;
}