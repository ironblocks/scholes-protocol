// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { HStack, VStack, Box } from '@chakra-ui/react'
import IlliquidPosition from './IlliquidPosition'
import OnChainContext from './OnChainContext'

function Liquidation({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [holders, setHolders] = React.useState([])

    const refreshHolders = async _ => {
        const longId = await cOrderBook.longOptionId()
        const shortId = await onChain.cScholesOption.getOpposite(longId)
        const numHolders = await onChain.cScholesOption.numHolders(shortId)
        let _holders = []
        for (let i = 0n; i < numHolders; i++) {
            const holder = await onChain.cScholesOption.getHolder(shortId, i)
            const canLiquidate = ! (await onChain.cScholesOption.isCollateralSufficient(holder, shortId, false/*entry*/))
console.log('requirement', holder, shortId, await onChain.cScholesOption.getCollateralRequirementThreshold(shortId, false))
            if (canLiquidate) _holders.push(holder)
        }
        setHolders(_holders);
    }

    React.useEffect(() => {
        onChain.signer.provider.on("block", refreshHolders);
        return () => onChain.signer.provider.off("block", refreshHolders);
    }, []);

    React.useEffect(() => {
        (async () => {
            await refreshHolders(0n/*dummy*/);
        }) ();
    }, [cOrderBook, onChain.address]);

    React.useEffect(() => {
        // Listening for Liquidate event
        const event = onChain.cScholesOption.filters.Liquidate(); // Define event filter
        const listener = onChain.cScholesOption.on(event, async (_) => {
            await refreshHolders()
        });

        // Clean up the effect
        return () => {
            onChain.cScholesOption.off(event, listener);
        };
    }, []);

    return (<VStack width='50%' p={4} borderRadius='md' shadow='lg' bg='gray.700'>
        <Box>Liquidation candidates:</Box>
        {holders.map((h)=><IlliquidPosition key={h} cOrderBook={cOrderBook} addressToLiquidate={h} />)}
        </VStack>);
}

export default Liquidation;