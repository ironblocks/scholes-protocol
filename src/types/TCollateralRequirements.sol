// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

// Only for short option holdings
struct TCollateralRequirements {
    uint256 entryCollateralRequirement; // Collateral requirement to enter 1 short option (expressed in base collateral tokens)
    uint256 maintenanceCollateralRequirement; // Collateral requirement to keep 1 short option without risking liquidation (expressed in base collateral tokens)
    uint256 timestamp; // Timestamp of the last update
}