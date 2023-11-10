// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

struct TTakerEntry {
    uint256 id;
    int256 amount;
    uint256 price;
}

struct TMakerEntry {
    int256 amount;
    uint256 price;
    uint256 expiration;
}

