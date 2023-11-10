// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import { Box, Text } from '@chakra-ui/react'
import aIERC20Metadata from '../artifacts/IERC20Metadata.json'
import aISpotPriceOracle from '../artifacts/ISpotPriceOracle.json'

function OptionDescription({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [underlying, setUnderlying] = React.useState(null)
    const [base, setBase] = React.useState(null)
    const [isCall, setIsCall] = React.useState(null)
    const [strike, setStrike] = React.useState(null)
    const [expiration, setExpiration] = React.useState(null)
    const [isAmerican, setIsAmerican] = React.useState(null)
    const [cOracle, setCOracle] = React.useState(null)
    const [spotPrice, setSpotPrice] = React.useState(null)

    const ierc20Symbol = async (addr) => {
        const cIerc20 = new ethers.Contract(addr, aIERC20Metadata.abi, onChain.signer);
        return await cIerc20.symbol();
    }

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
            setUnderlying(await ierc20Symbol(await onChain.cScholesOption.getUnderlyingToken(id)))
            setBase(await ierc20Symbol(await onChain.cScholesOption.getBaseToken(id)))
            setIsCall(await onChain.cScholesOption.isCall(id))
            setStrike(await onChain.cScholesOption.getStrike(id))
            setExpiration(await onChain.cScholesOption.getExpiration(id))
            setIsAmerican(await onChain.cScholesOption.isAmerican(id))
            const cO = new ethers.Contract(await onChain.cScholesOption.spotPriceOracle(id), aISpotPriceOracle.abi, onChain.signer)
            setCOracle(cO)
            await updatePrice(cO)
        }) ();
    }, [cOrderBook]); // On load

    return (<Box bg='gray.700' borderRadius='md' shadow='lg' p={2}>
        <Text>{underlying}/{base} {isCall?'Call':'Put'}</Text>
        <Text>Strike price: {strike && ethers.formatEther(strike)}</Text>
        <Text>Expiration: {expiration && new Date(Number(expiration) * 1000).toString()} {null !== isAmerican && (isAmerican ? "American" : "European") } </Text>
        <Text>Spot price from liquidation oracle: {spotPrice}</Text>
    </Box>);
}

export default OptionDescription;