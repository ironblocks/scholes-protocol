// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Box, Text } from '@chakra-ui/react'
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import aMockERC20 from '../artifacts/MockERC20.json'
import MockToken from './MockToken'

function MockTokens({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [cBase, setCBase] = React.useState(null)
    const [cUnderlying, setCUnderlying] = React.useState(null)

    React.useEffect(() => {
        (async () => {
            const id = await onChain.cScholesOption.getOpposite(await cOrderBook.longOptionId()); // Get the Short Option ID
            setCBase(new ethers.Contract(await onChain.cScholesOption.getBaseToken(id), aMockERC20.abi, onChain.signer));
            setCUnderlying(new ethers.Contract(await onChain.cScholesOption.getUnderlyingToken(id), aMockERC20.abi, onChain.signer));
        }) ();
    }, [cOrderBook]);

    if (!cBase || !cUnderlying) return;
    return (<Box bg='red.700' borderRadius='md' shadow='lg' p={2}>
        <Text>Mock tokens - for testing only:</Text>
        <MockToken cToken={cBase} />
        <MockToken cToken={cUnderlying} />
    </Box>);
}

export default MockTokens;