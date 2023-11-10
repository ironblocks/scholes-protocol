// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { VStack, Text } from '@chakra-ui/react'
import OnChainContext from './OnChainContext'
import { ethers } from 'ethers'
import aOrderBook from '../artifacts/OrderBook.json'
import OptionDescription from './OptionDescription'
import Collaterals from './Collaterals'
import Holding from './Holding'
import NewOrder from './NewOrder'
import OrderBook from './OrderBook'
import MockTokens from './MockTokens'
import MockPrice from './MockPrice'
import MockTime from './MockTime'
import Liquidation from './Liquidation'
import CommitSettlementPrice from './CommitSettlementPrice'

function OptionTrading({ obIndex }) {
    const onChain = React.useContext(OnChainContext)
    const [cOrderBook, setCOrderBook] = React.useState(null);

    React.useEffect(() => {
        if (null === obIndex) return;
        (async () => {
            const obAddr = await onChain.cOrderBookList.getOrderBook(obIndex);
            setCOrderBook(new ethers.Contract(obAddr, aOrderBook.abi, onChain.signer));
        }) ();
    }, [onChain.signer, obIndex]);

    if (null === cOrderBook) return(<Text><br/>Please make your selection on the left!</Text>)
    return (<VStack>
        <br/>
        <OptionDescription cOrderBook={cOrderBook} />
        <Holding cOrderBook={cOrderBook} />
        <Collaterals cOrderBook={cOrderBook} />
        <NewOrder cOrderBook={cOrderBook} />
        <OrderBook cOrderBook={cOrderBook} />
        <Liquidation cOrderBook={cOrderBook} />
        <CommitSettlementPrice cOrderBook={cOrderBook} />
        <MockTokens cOrderBook={cOrderBook} />
        <MockPrice cOrderBook={cOrderBook} />
        <MockTime />
    </VStack>);
}

export default OptionTrading;