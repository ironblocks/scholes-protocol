// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "chainlink/interfaces/AggregatorV3Interface.sol";

import "./interfaces/ISpotPriceOracle.sol";

contract SpotPriceOracle is VennFirewallConsumer, ISpotPriceOracle {
    AggregatorV3Interface public chainLinkPriceFeed;
    IERC20Metadata public spotToken;
    IERC20Metadata public baseToken;
    bool public isInverse;

    uint256 mockPrice; // == 0

    constructor (AggregatorV3Interface priceFeed, IERC20Metadata spot, IERC20Metadata base, bool _isInverse) {
        chainLinkPriceFeed = priceFeed;
        spotToken = spot;
        baseToken = base;
        isInverse  = _isInverse;
    }

    function description() external view returns (string memory) {
        return chainLinkPriceFeed.description();
    }

    function getPrice() public view returns (uint256 price) {
        if (mockPrice != 0) return mockPrice;
        (, int256 feedPrice, , , ) = chainLinkPriceFeed.latestRoundData();
        require(feedPrice > 0, "Invalid price"); // Reverts, peventing liquidations at invalid price
        price = (uint256(feedPrice) * 10 ** decimals()) / 10 ** chainLinkPriceFeed.decimals();
    }

    // DANGEROUS!!! WARNING - Use only for testing! Remove before mainnet deployment.
    function setMockPrice(uint256 price) external firewallProtected {
        // require(msg.sender == owner, "Unauthorized");
        mockPrice = price;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function getTokens() external view returns (IERC20Metadata base, IERC20Metadata spot) {
        return (baseToken, spotToken);
    }

    function toSpot(uint256 baseAmount, uint256 price) public view returns (uint256 spotAmount) {
        spotAmount = ((baseAmount * 10 ** spotToken.decimals()) / 10 ** baseToken.decimals()); // Decimal conversion
        if (isInverse) {
            spotAmount = (spotAmount * price) / 10 ** decimals();
        } else {
            spotAmount = (spotAmount * 10 ** decimals()) / price;
        }
    }

    function toSpot(uint256 baseAmount) external view returns (uint256) {
        return toSpot(baseAmount, getPrice());
    }

    function toBase(uint256 spotAmount, uint256 price) public view returns (uint256 baseAmount) {
        baseAmount = ((spotAmount * 10 ** baseToken.decimals()) / 10 ** spotToken.decimals()); // Decimal conversion
        if (isInverse) {
            baseAmount = (baseAmount * 10 ** decimals()) / price;
        } else {
            baseAmount = (baseAmount * price) / 10 ** decimals();
        }
    }

    function toBase(uint256 spotAmount) external view returns (uint256) {
        return toBase(spotAmount, getPrice());
    }

    function toBaseFromOption(uint256 optionAmount, uint256 price) public view returns (uint256 baseAmount) {
        baseAmount = ((optionAmount * 10 ** baseToken.decimals()) / 10 ** 18); // Decimal conversion
        baseAmount = (baseAmount * price) / 10 ** decimals();
    }

    function toOptionFromBase(uint256 baseAmount, uint256 price) public view returns (uint256 optionAmount) {
        optionAmount = ((baseAmount * 10 ** 18) / 10 ** baseToken.decimals()); // Decimal conversion
        optionAmount = (optionAmount * 10 ** decimals()) / price;
    }
}