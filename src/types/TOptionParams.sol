// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

struct TOptionParams {
    IERC20Metadata underlying;
    IERC20Metadata base;
    uint256 strike;
    uint256 expiration;
    bool isCall;
    bool isAmerican;
    bool isLong;
    uint256 settlementPrice;
}