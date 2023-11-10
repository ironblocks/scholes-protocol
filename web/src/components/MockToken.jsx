// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Flex, NumberInput, NumberInputField, NumberInputStepper, NumberDecrementStepper, NumberIncrementStepper, Text, Button } from '@chakra-ui/react'
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'

function MockToken({cToken}) {
    const onChain = React.useContext(OnChainContext)
    const [symbol, setSymbol] = React.useState(null)
    const [decimals, setDecimals] = React.useState(null)
    const [amount, setAmount] = React.useState('0')

    React.useEffect(() => {
        (async () => {
            setSymbol(await cToken.symbol());
            setDecimals(await cToken.decimals());
        }) ();
    }, [cToken]);

    const mint = async () => {
        try{
            const tx = await cToken.mint(ethers.parseUnits(amount, decimals))
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    return (<Flex>
        <Text>{symbol}</Text>
        <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setAmount(valueAsString)} >
        <NumberInputField />
        <NumberInputStepper>
            <NumberIncrementStepper />
            <NumberDecrementStepper />
        </NumberInputStepper>
        </NumberInput>
        <Button color='black' bg='green' onClick={mint}>Get</Button>
    </Flex>);
}

export default MockToken;