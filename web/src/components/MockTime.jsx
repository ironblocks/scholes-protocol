// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Box, Input, Text, Button } from '@chakra-ui/react'
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import aTimeOracle from '../artifacts/ITimeOracle.json'

function MockTime() {
    const onChain = React.useContext(OnChainContext)
    const [blockTime, setBlockTime] = React.useState(null)
    const [timeToSet, setTimeToSet] = React.useState(null)

    const onUpdate = async () => {
        const cTimeOracle = new ethers.Contract(await onChain.cScholesOption.timeOracle(), aTimeOracle.abi, onChain.signer);
        setBlockTime(Number(await cTimeOracle.getTime()) * 1000);
    };

    React.useEffect(() => {
        (async () => {
            await onUpdate();
        }) ();
    }); // Run on each render because onUpdate is a closure

    React.useEffect(() => {
        onChain.signer.provider.on("block", onUpdate);
        return () => onChain.signer.provider.off("block", onUpdate);
    }); // Run on each render because onUpdate is a closure

    const setTime = async () => {
        if (!timeToSet) return;
        const cTimeOracle = new ethers.Contract(await onChain.cScholesOption.timeOracle(), aTimeOracle.abi, onChain.signer);
        try{
            const tx = await cTimeOracle.setMockTime(Date.parse(timeToSet)/1000)
            const r = await tx.wait()
            await onUpdate()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const actualTime = async () => {
        const cTimeOracle = new ethers.Contract(await onChain.cScholesOption.timeOracle(), aTimeOracle.abi, onChain.signer);
        try{
            const tx = await cTimeOracle.setMockTime(0n)
            const r = await tx.wait()
            await onUpdate()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    return (<Box bg='red.700' borderRadius='md' shadow='lg' p={2}>
        <Text>Mock time - for testing only:</Text>
        <Text>Time: {blockTime && new Date(blockTime).toString()}</Text>
        <Input placeholder="Select Date and Time" size="md" type="datetime-local" onChange={event => setTimeToSet(event.target.value)} />
        <Button color='black' bg='green' onClick={setTime}>Set</Button> &nbsp;
        <Button color='black' bg='green' onClick={actualTime}>Actual</Button>
    </Box>);
}

export default MockTime;