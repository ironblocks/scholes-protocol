// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./ISpotPriceOracle.sol";

interface ISpotPriceOracleApprovedList {
    function addOracle(ISpotPriceOracle oracle) external;
    function getOracle(IERC20Metadata spotToken, IERC20Metadata baseToken) external view returns (ISpotPriceOracle);
    function isApproved(ISpotPriceOracle oracle) external returns (bool);
}