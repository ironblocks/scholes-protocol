// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Box, Button, Text } from '@chakra-ui/react'
import OnChainContext from './OnChainContext'

function IlliquidPosition({cOrderBook, addressToLiquidate}) {
    const onChain = React.useContext(OnChainContext)

    const onLiquidate = async () => {
        try{
            const longId = await cOrderBook.longOptionId()
            const shortId = await onChain.cScholesOption.getOpposite(longId)
console.log('can liquidate', ! (await onChain.cScholesOption.isCollateralSufficient(addressToLiquidate, shortId, false/*entry*/)))
const b = await onChain.cScholesCollateral.balances(addressToLiquidate, shortId)
console.log('col balances', b[0], b[1])
const ob = await onChain.cScholesOption.balanceOf(addressToLiquidate, shortId)
console.log('option bal', ob)
console.log('liquidation requirement', addressToLiquidate, shortId, await onChain.cScholesOption.collateralRequirement(ob, shortId, false))
console.log('liquidate', addressToLiquidate, shortId)
            const tx = await onChain.cScholesOption.liquidate(addressToLiquidate, shortId)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash)
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    if (!onChain.address) return;
    return (<Box width='100%' borderRadius='md' shadow='lg' bg='black'>
        <Text>{addressToLiquidate} {addressToLiquidate === onChain.address && '(me)'}</Text>
        <Button onClick={onLiquidate} colorScheme='red' isDisabled={addressToLiquidate === onChain.address} >Liquidate</Button>       
    </Box>);
}

export default IlliquidPosition;