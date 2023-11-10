// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "./types/TOptionParams.sol";
import "./types/TCollateralRequirements.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IScholesOption.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IOrderBookList.sol";
import "./OrderBook.sol";

contract OrderBookList is IOrderBookList, Ownable {
    IOrderBook[] public list;
    IScholesOption public scholesOptions;

    constructor (IScholesOption _scholesOptions) {
        scholesOptions = _scholesOptions;
    }

    function getLength() external view returns (uint256) {
        return list.length;
    }
    
    function getOrderBook(uint256 index) external view returns (IOrderBook) {
        require(index < list.length, "Out of bounds");
        return list[index];
    }

    function createScholesOptionPair(TOptionParams memory longOptionParams, TCollateralRequirements memory collateralReqShort) external {
        (uint256 longId, ) = scholesOptions.createOptionPair(longOptionParams, collateralReqShort);
        IOrderBook ob = new OrderBook(scholesOptions, longId);
        scholesOptions.authorizeExchange(longId, address(ob));
        list.push(ob);
    }
}