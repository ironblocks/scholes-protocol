// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

// Only for short option holdings
struct TCollateralRequirements {
    uint256 entryCollateralRequirement; // Ratio collateral / strike in 18 decimals expressed in base currency (token)
    uint256 maintenanceCollateralRequirement; // Ratio collateral / strike in 18 decimals expressed in base currency (token)
    uint256 liquidationPenalty; // Ratio liquidation penalty amount / missing collateral in 18 decimals
}