// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "./interfaces/ITimeOracle.sol";

contract MockTimeOracle is VennFirewallConsumer, ITimeOracle {
    uint256 mockTime;

    // DANGEROUS!!! WARNING - Use only for testing! Remove before mainnet deployment.
    function setMockTime(uint256 time) external firewallProtected {
        // Instead of using the foundty cheat code vm.warp(time).
        // This is useful when deployed on testnet and not only on Anvil.
        mockTime = time;
    } 

    function getTime() external view returns (uint256) {
        if (0 == mockTime) return block.timestamp;
        else return mockTime;
    }
}