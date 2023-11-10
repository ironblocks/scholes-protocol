// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { HStack, VStack, Box } from '@chakra-ui/react'
import OnChainContext from './OnChainContext'
import Order from './Order';

function OrderBook({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [bids, setBids] = React.useState([])
    const [offers, setOffers] = React.useState([])

    const refreshOrderBook = async () => {
        const n = await cOrderBook.numOrders()
        let b = []
        let o = []
        for (let i = 0n; i < n[0]; i++) {
            const s = await cOrderBook.status(true, i);
            b.push({amount: s[0], price: s[1], expiration: s[2], owner: s[3], id: i, isBid: true})
        }
        for (let i = 0n; i < n[1]; i++) {
            const s = await cOrderBook.status(false, i);
            o.push({amount: s[0], price: s[1], expiration: s[2], owner: s[3], id: i, isBid: false})
        }
        b.sort((a, b) => { return a.price<b.price ? 1 : -1 })
        o.sort((a, b) => { return a.price>b.price ? 1 : -1 })
        setBids(b);
        setOffers(o);
    }

    React.useEffect(() => {
        (async () => {
            await refreshOrderBook();
        }) ();
    }, [cOrderBook, onChain.address]);

    React.useEffect(() => {
        // Listening for Make event
        const event = cOrderBook.filters.Make(); // Define event filter
        const listener = cOrderBook.on(event, async (_) => {
            await refreshOrderBook()
        });

        // Clean up the effect
        return () => {
            cOrderBook.off(event, listener);
        };
    }, []);

    React.useEffect(() => {
        // Listening for Take event
        const event = cOrderBook.filters.Take(); // Define event filter
        const listener = cOrderBook.on(event, async (_) => {
            await refreshOrderBook()
        });

        // Clean up the effect
        return () => {
            cOrderBook.off(event, listener);
        };
    }, []);

    React.useEffect(() => {
        // Listening for Cancel event
        const event = cOrderBook.filters.Cancel(); // Define event filter
        const listener = cOrderBook.on(event, async (_) => {
            await refreshOrderBook()
        });

        // Clean up the effect
        return () => {
            cOrderBook.off(event, listener);
        };
    }, []);

    return (<HStack width='100%' p={4} align='top'>
        <VStack width='50%' p={4} borderRadius='md' shadow='lg' bg='gray.700'>
        <Box>Bids:</Box>
        {bids.map((o)=><Order key={o.id} cOrderBook={cOrderBook} order={o} />)}
        </VStack>
        <VStack width='50%' p={4} borderRadius='md' shadow='lg' bg='gray.700'>
        <Box>Offers:</Box>
        {offers.map((o)=><Order key={o.id} cOrderBook={cOrderBook} order={o} />)}
        </VStack>
    </HStack>);
}

export default OrderBook;