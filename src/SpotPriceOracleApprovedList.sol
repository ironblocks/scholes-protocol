// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "openzeppelin-contracts/access/Ownable.sol";

import "./interfaces/ISpotPriceOracle.sol";
import "./interfaces/ISpotPriceOracleApprovedList.sol";

contract SpotPriceOracleApprovedList is VennFirewallConsumer, ISpotPriceOracleApprovedList, Ownable {
    mapping (address => bool) approved;
    mapping (address => mapping (address => ISpotPriceOracle)) oracles; // spot => (base => oracle)

    function addOracle(ISpotPriceOracle oracle) external onlyOwner firewallProtected {
        approved[address(oracle)] = true;
        oracles[address(oracle.spotToken())][address(oracle.baseToken())] = oracle;
    }

    function getOracle(IERC20Metadata spotToken, IERC20Metadata baseToken) external view returns (ISpotPriceOracle) {
        return oracles[address(spotToken)][address(baseToken)];
    }

    function isApproved(ISpotPriceOracle oracle) external view returns (bool) {
        return approved[address(oracle)];
    }
}