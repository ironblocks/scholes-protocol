// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;
import "../types/TSweepOrderParams.sol";

interface IOrderBook {
    event ChangeId(bool indexed isBid, uint256 indexed oldId, uint256 indexed newId);
    event Take(uint256 indexed id, address indexed maker, address indexed taker, int256 amount);
    event Make(uint256 indexed id, address indexed maker, int256 amount, uint256 price, uint256 expiration);
    event Cancel(bool indexed isBid, uint256 indexed id);

    function longOptionId() external view returns (uint256);
    function bids(uint256 id) external view returns (int256 amount, uint256 price, uint256 expiration, address owner);
    function offers(uint256 id) external view returns (int256 amount, uint256 price, uint256 expiration, address owner);

    function make(int256 amount, uint256 price, uint256 expiration) external returns (uint256 id);
    function take(uint256 id, int256 amount, uint256 price) external;
    function sweepAndMake(bool forceFunding, TTakerEntry[] memory makers, TMakerEntry memory toMake) external returns (uint256 id);
    function cancel(bool isBid, uint256 id) external;
    function status(bool isBid, uint256 id) external view returns (int256 amount, uint256 price, uint256 expiration, address owner);
    function numOrders() external view returns (uint256 numBids, uint256 numOffers);
    function isMine(bool isBid, uint256 id) external view returns (bool);
}