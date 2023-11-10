// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import { Text, Box, Button } from '@chakra-ui/react'
import OnChainContext from './OnChainContext'
import aISpotPriceOracle from '../artifacts/ISpotPriceOracle.json'
import aTimeOracle from '../artifacts/ITimeOracle.json'

function CommitSettlementPrice({cOrderBook}) {
    const notAvailable = 'N/A'
    const onChain = React.useContext(OnChainContext)
    const [settlementPrice, setSettlementPrice] = React.useState(notAvailable)
    const [blockTime, setBlockTime] = React.useState(null)
    const [expiration, setExpiration] = React.useState(null)
    
    React.useEffect(() => {
        (async () => {
            const id = await cOrderBook.longOptionId()
            setExpiration(await onChain.cScholesOption.getExpiration(id))
            await updateTime(0n/*dummy*/)
            await getSettlementPrice()
        }) ()
    }, [cOrderBook]); // On load

    const onCommit = async (mockPrice) => {
        try {
            const id = await cOrderBook.longOptionId()
            await onChain.cScholesOption.setSettlementPrice(id)
            const r = await tx.wait()
            await getSettlementPrice()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const getSettlementPrice = async () => {
        const id = await cOrderBook.longOptionId()
        const price = await onChain.cScholesOption.getSettlementPrice(id)
        if (0n === price) return; // Not (yet) available
        const cO = new ethers.Contract(await onChain.cScholesOption.spotPriceOracle(id), aISpotPriceOracle.abi, onChain.signer)
        const decimals = await cO.decimals();
        setSettlementPrice(ethers.formatUnits(price, decimals))
    }

    const updateTime = async (_) => {
        // const block = await onChain.signer.provider.getBlock(blockNumber);
        // setTimestamp(block.timestamp);
        const cTimeOracle = new ethers.Contract(await onChain.cScholesOption.timeOracle(), aTimeOracle.abi, onChain.signer);
        setBlockTime(await cTimeOracle.getTime());
    };

    React.useEffect(() => {
        onChain.signer.provider.on("block", updateTime);
        return () => onChain.signer.provider.off("block", updateTime);
    }, []);

    const canCommit = () => {
        if (settlementPrice !== notAvailable) return false
        return blockTime > expiration
    }

    return (<Box bg='purple.700' borderRadius='md' shadow='lg' p={2}>
        <Text>Settlement price for exercise: {settlementPrice !== notAvailable ? settlementPrice : 'N/A'}</Text>
        <Button color='black' bg='green' isDisabled={! canCommit()} onClick={onCommit} >Commit</Button>
    </Box>);
}

export default CommitSettlementPrice;