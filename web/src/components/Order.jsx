// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import { Box, Button } from '@chakra-ui/react'
import {
    Popover,
    PopoverTrigger,
    PopoverContent,
    PopoverHeader,
    PopoverBody,
    PopoverFooter,
    PopoverArrow,
    PopoverCloseButton,
    PopoverAnchor,
  } from '@chakra-ui/react'
  import {
    Slider,
    SliderTrack,
    SliderFilledTrack,
    SliderThumb,
    SliderMark,
  } from '@chakra-ui/react'
  import OnChainContext from './OnChainContext'

function Order({cOrderBook, order}) {
    const onChain = React.useContext(OnChainContext)

    const onOrderClicked = async () => {
        if (onChain.address.toLowerCase() === order.owner.toString().toLowerCase()) {
            await cancelOrder()
        }
    }

    const cancelOrder = async () => {
        try{
            const tx = await cOrderBook.cancel(order.isBid, order.id)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const takeOrder = async (sliderValue) => {
        try{
console.log("order.amount", order.amount, sliderValue, order.price, - order.amount * BigInt(sliderValue) / 100n)
            const tx = await cOrderBook.take(order.id, - order.amount * BigInt(sliderValue) / 100n, order.price)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash)
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const Body = () => {
        const [sliderValue, setSliderValue] = React.useState(100)

        if (onChain.address.toLowerCase() === order.owner.toString().toLowerCase()) {
            return (<Box align='right'><Button onClick={cancelOrder} colorScheme='red'>Cancel order</Button></Box>)
        }
        return(<Box pt={6} pb={2} bg='black' align='right'>
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
            <br/>
            <Button onClick={() => takeOrder(sliderValue)} colorScheme='green'>Take</Button>
        </Box>)
    }

    const abs = x => {
        return x < 0n ? x * -1n : x
    }

    if (!onChain.address) return;
    return (<Box width='100%' borderRadius='md' shadow='lg' bg={order.isBid ? 'black' : 'black'}>
        <Popover>
            <PopoverTrigger>
                <Box>
                    {ethers.formatUnits(abs(order.amount), 18) + 
                    " @ " +
                    ethers.formatUnits(order.price, 18) + 
                    (onChain.address.toLowerCase() === order.owner.toString().toLowerCase() ? " (me)" : "")}
                </Box>
            </PopoverTrigger>
            <PopoverContent bg='black' >
                <PopoverArrow />
                <PopoverCloseButton />
                <PopoverHeader>
                    {ethers.formatUnits(abs(order.amount), 18) + " @ " + ethers.formatUnits(order.price, 18)} &nbsp;
                    Id: {order.id.toString()} <br/> 
                    Issuer: {order.owner.toString() + (onChain.address.toLowerCase() === order.owner.toString().toLowerCase() ? " (me)" : "")}
                </PopoverHeader>
                <PopoverBody><Body/></PopoverBody>
            </PopoverContent>
        </Popover>        
    </Box>);
}

export default Order;