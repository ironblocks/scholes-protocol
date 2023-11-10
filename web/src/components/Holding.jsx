// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import { Box, Text, Button, Checkbox } from '@chakra-ui/react'
import aTimeOracle from '../artifacts/ITimeOracle.json'
import {
    Slider,
    SliderTrack,
    SliderFilledTrack,
    SliderThumb,
    SliderMark,
  } from '@chakra-ui/react'

function Holding({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [myHolding, setMyHolding] = React.useState(null)
    const [blockTime, setBlockTime] = React.useState(null)
    const [expiration, setExpiration] = React.useState(null)
    const [isAmerican, setIsAmerican] = React.useState(null)
    const [toUnderlying, setToUnderlying] = React.useState(true)
    const [sliderValue, setSliderValue] = React.useState(100)
    
    const refreshHolding = async () => {
        const longId = await cOrderBook.longOptionId();
        const longBal = await onChain.cScholesOption.balanceOf(onChain.address, longId);
        const shortId = await onChain.cScholesOption.getOpposite(longId);
        const shortBal = await onChain.cScholesOption.balanceOf(onChain.address, shortId);
        if (longBal > 0n && shortBal > 0n) console.error("Holding both long and short positions:", longBal, shortBal);
        setMyHolding(longBal - shortBal);
        setExpiration(await onChain.cScholesOption.getExpiration(longId));
        setIsAmerican(await onChain.cScholesOption.isAmerican(longId));
    };

    React.useEffect(() => {
        (async () => {
            const longId = await refreshHolding()
        }) ();
    }, [onChain.signer, onChain.address, cOrderBook]);

    React.useEffect(() => {
        // Listening for TransferSingle event
        const event = onChain.cScholesOption.filters.TransferSingle(); // Define event filter
        const listener = onChain.cScholesOption.on(event, async (_) => {
            await refreshHolding()
        });

        // Clean up the effect
        return () => {
            onChain.cScholesOption.off(event, listener);
        };
    }, [onChain.signer, onChain.address, cOrderBook]);

    React.useEffect(() => {
        // Listening for TransferBatch event
        const event = onChain.cScholesOption.filters.TransferBatch(); // Define event filter
        const listener = onChain.cScholesOption.on(event, async (_) => {
            await refreshHolding()
        });

        // Clean up the effect
        return () => {
            onChain.cScholesOption.off(event, listener);
        };
    }, [onChain.signer, onChain.address, cOrderBook]);

    const onUpdate = async (blockNumber) => {
        // const block = await onChain.signer.provider.getBlock(blockNumber);
        // setTimestamp(block.timestamp);
        const cTimeOracle = new ethers.Contract(await onChain.cScholesOption.timeOracle(), aTimeOracle.abi, onChain.signer);
        setBlockTime(await cTimeOracle.getTime());
    };

    React.useEffect(() => {
        onChain.signer.provider.on("block", onUpdate);
        return () => onChain.signer.provider.off("block", onUpdate);
    }, []);

    const onExercise = async () => {
        const longId = await cOrderBook.longOptionId();
        let holders = [];
        let amounts = [];
        if (await onChain.cScholesOption.isAmerican(longId) && blockTime <= expiration) {
            // Unexpired American option
            // Fund conterparty holders and amounts to match the amount
console.error("Not implemented");
            return;
        } else {
            // Expired option
            if (blockTime <= expiration) return; // Bug - unexpired European option; button should have been disabled
            // Nothing to do
        }
        try{
            const tx = await onChain.cScholesOption.exercise(longId, (myHolding * BigInt(sliderValue)) / 100n, toUnderlying, holders, amounts)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }
        
    const onSettle = async () => {
        const longId = await cOrderBook.longOptionId();
        const shortId = await onChain.cScholesOption.getOpposite(longId);
        try{
            const tx = await onChain.cScholesOption.settle(shortId)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }
                
    const canExercise = () => {
        if (myHolding!==null && myHolding<=0) console.error("Exercise button misplaced!");
        if (isAmerican === null) return false;
        if (expiration === null) return false;
        if (isAmerican) return true;
        if (blockTime > expiration) return true;
        return false;
    }

    const canSettle = () => {
        if (myHolding!==null && myHolding>=0) console.error("Settle button misplaced!");
        if (blockTime > expiration) return true;
        return false;
    }

    return (<Box bg='gray.700' borderRadius='md' shadow='lg' p={2}>
        <Text>Holding: </Text>
        <Text color={(!myHolding?'white':(myHolding>0n?'green':'red'))} >{myHolding!==null && ethers.formatUnits(myHolding, 18)}</Text>
        {myHolding!==null && myHolding>0 && <>
            <Text>Amount:</Text>
            <Slider defaultValue={100} aria-label='slider-ex-6' onChange={(val) => setSliderValue(val)}>
                <SliderMark
                value={sliderValue}
                textAlign='center'
                bg='white'
                color='black'
                mt='-10'
                ml='-5'
                w='12'
                >
                {sliderValue}%
                </SliderMark>
                <SliderTrack>
                <SliderFilledTrack />
                </SliderTrack>
                <SliderThumb />
            </Slider>
            <Checkbox defaultChecked>To Underlying</Checkbox>
            <Button bg='purple.700' isDisabled={!canExercise()} onClick={onExercise} >Exercise</Button></>}
        {myHolding!==null && myHolding<0 && <Button bg='purple.700' isDisabled={!canSettle()} onClick={onSettle} >Settle</Button>}
    </Box>);
}

export default Holding;