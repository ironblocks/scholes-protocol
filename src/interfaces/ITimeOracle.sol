// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ITimeOracle {
    function setMockTime(uint256 time) external; // DANGEROUS!!! WARNING - Use only for testing! Remove before mainnet deployment.

    function getTime() external view returns (uint256);
}