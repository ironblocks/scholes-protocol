// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "./types/TOptionParams.sol";
import "./types/TCollateralRequirements.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IScholesOption.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IOrderBookList.sol";
import "./OrderBook.sol";

contract OrderBookList is VennFirewallConsumer, IOrderBookList, Ownable {
    IOrderBook[] public list;
    IScholesOption public scholesOptions;
    address feeCollector;

    constructor (IScholesOption _scholesOptions) {
        scholesOptions = _scholesOptions;
        feeCollector = tx.origin; // For now
    }

    function getLength() external view returns (uint256) {
        return list.length;
    }

    error OutOfBounds();
    
    function getOrderBook(uint256 index) external view returns (IOrderBook) {
        if (index >= list.length) revert OutOfBounds();
        return list[index];
    }

    function createScholesOptionPair(TOptionParams memory longOptionParams) external {
        (uint256 longId, ) = scholesOptions.createOptionPair(longOptionParams);
        IOrderBook ob = new OrderBook(scholesOptions, longId, feeCollector);
        scholesOptions.authorizeExchange(longId, address(ob));
        emit Create(list.length, address(ob), longId);
        list.push(ob);
    }

    function removeOrderBook(uint256 index) external {
        if (index >= list.length) revert OutOfBounds();
        IOrderBook ob = list[index];
        emit Remove(index, address(ob), ob.longOptionId());
        ob.destroy(); // Clear storage
        list[index] = IOrderBook(address(0)); // Remove from list without rearranging
    }
}