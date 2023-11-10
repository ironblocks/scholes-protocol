// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

contract Volatility {
    uint256 length;
    uint256 timeModulo;
    uint256[] open;
    uint256[] close;
    uint256[] high;
    uint256[] low;
    uint256 index;
    uint256 public lastVolatility; // == 0
    uint256 lastTs;

    constructor (uint256 _length, uint256 _timeModulo) {
        length = _length;
        timeModulo = _timeModulo;
        open = new uint256[](length);
        close = new uint256[](length);
        high = new uint256[](length);
        low = new uint256[](length);
    }   

    function isSameBar(uint256 ts, uint256 _lastTs) private view returns (bool) {
        return (ts / timeModulo) == (_lastTs / timeModulo);
    }

    function update(uint256 ts, uint256 price) public {
        if (isSameBar(ts, lastTs)) {
            uint256 oldTR = trueRange(index); // will be updated
            close[index] = price;
            if (price > high[index]) high[index] = price;
            if (price < low[index]) low[index] = price;
            if (lastVolatility != 0) {
                lastVolatility += (trueRange(index) - oldTR) / length;
            }
        } else {
            bool toInit = index == length - 1;
            index = (index + 1) % length;
            uint256 oldTR = trueRange(index); // will be thrown away
            open[index] = price;
            close[index] = price;
            high[index] = price;
            low[index] = price;
            if (toInit) lastVolatility = averageTrueRange();
            else {
                lastVolatility += (trueRange(index) - oldTR) / length;
            }
        }
        lastTs = ts;
    }

    function trueRange(uint256 pos) private view returns (uint256 tr) {
        uint256 prev = (pos - 1 + length) % length;
        tr = high[pos] - low[pos];
        uint256 h2c = high[pos] <= close[prev] ? 0 : high[pos] - close[prev];
        uint256 c2l = close[prev] <= low[pos] ? 0 : close[prev] - low[pos];
        if (h2c > tr) tr = h2c;
        if (c2l > tr) tr = c2l;
    }

    function averageTrueRange() private view returns (uint256 atr) {
        uint256 sum = 0;
        for (uint256 i = 0; i < length; i++) {
            sum += trueRange((i + length) % length);
        }
        atr = sum / length;
    }

    function volatility() public view returns (uint256) {
        return lastVolatility;
    }
}