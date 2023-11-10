// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import { Text, Box, Button, NumberInput, NumberInputField, NumberInputStepper, NumberIncrementStepper, NumberDecrementStepper } from '@chakra-ui/react'
import OnChainContext from './OnChainContext'
import aISpotPriceOracle from '../artifacts/ISpotPriceOracle.json'

function MockPrice({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [spotPrice, setSpotPrice] = React.useState(null)
    const [price, setPrice] = React.useState("0")
    const [cOracle, setCOracle] = React.useState(null)
    
    const updatePrice = async cO => {
        setSpotPrice(ethers.formatUnits(await cO.getPrice(), await cO.decimals()))
    }

    const onUpdate = async _ => {
        await updatePrice(cOracle)
    }
        
    React.useEffect(() => {
        onChain.signer.provider.on("block", onUpdate);
        return () => onChain.signer.provider.off("block", onUpdate);
    }, [cOracle]); // onUpdate is a closure, so re-subscribe with a new onUpdate when cOracle changes

    React.useEffect(() => {
        (async () => {
            const id = await cOrderBook.longOptionId()
            const cO = new ethers.Contract(await onChain.cScholesOption.spotPriceOracle(id), aISpotPriceOracle.abi, onChain.signer)
            setCOracle(cO)
            await updatePrice(cO)
        }) ();
    }, [cOrderBook]); // On load

    const setMockPrice = async (mockPrice) => {
        try {
            const tx = await cOracle.setMockPrice(mockPrice)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const mockPrice = async () => {
        const p = ethers.parseUnits(price, 18);
        await setMockPrice(p)
    }

    const unmockPrice = async () => {
        await setMockPrice(0n);
    }

    return (<Box bg='red.700' borderRadius='md' shadow='lg' p={2}>
        <Text>Mock price - for testing only:</Text>
        <Text>Spot price from liquidation oracle: {spotPrice}</Text>
        <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setPrice(valueAsString)} >
        <NumberInputField />
        <NumberInputStepper>
            <NumberIncrementStepper />
            <NumberDecrementStepper />
        </NumberInputStepper>
        </NumberInput>
        <Button color='black' bg='red' onClick={mockPrice}>Set</Button> &nbsp;
        <Button color='black' bg='green' onClick={unmockPrice}>Reset</Button> &nbsp;
    </Box>);
}

export default MockPrice;