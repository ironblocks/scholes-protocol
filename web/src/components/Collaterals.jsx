// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Box, Text, SimpleGrid, NumberInput, NumberInputField, NumberInputStepper, NumberDecrementStepper, NumberIncrementStepper, Button } from '@chakra-ui/react'
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import aIERC20Metadata from '../artifacts/IERC20Metadata.json'

function Collaterals({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [sid, setSid] = React.useState(null)
    const [cBase, setCBase] = React.useState(null)
    const [cUnderlying, setCUnderlying] = React.useState(null)
    const [baseBalance, setBaseBalance] = React.useState(null)
    const [underlyingBalance, setUnderlyingBalance] = React.useState(null)
    const [baseSymbol, setBaseSymbol] = React.useState(null)
    const [underlyingSymbol, setUnderlyingSymbol] = React.useState(null)
    const [baseDecimals, setBaseDecimals] = React.useState(null)
    const [underlyingDecimals, setUnderlyingDecimals] = React.useState(null)
    const [baseCollateralBalance, setBaseCollateralBalance] = React.useState(null)
    const [underlyingCollateralBalance, setUnderlyingCollateralBalance] = React.useState(null)
    const [baseAmount, setBaseAmount] = React.useState('0')
    const [underlyingAmount, setUnderlyingAmount] = React.useState('0')

    const refreshBalances = async () => {
        if (!onChain.address || !cUnderlying || !cBase || null === sid || null === baseDecimals || null === underlyingDecimals) return;
        setBaseBalance(ethers.formatUnits(await cBase.balanceOf(onChain.address), baseDecimals))
        setUnderlyingBalance(ethers.formatUnits(await cUnderlying.balanceOf(onChain.address), underlyingDecimals))
        const c = await onChain.cScholesCollateral.balances(onChain.address, sid);
        setBaseCollateralBalance(ethers.formatUnits(c[0], baseDecimals));
        setUnderlyingCollateralBalance(ethers.formatUnits(c[1], underlyingDecimals));
    }

    React.useEffect(() => {
        (async () => {
            refreshBalances();
        }) ();
    }, [cUnderlying, cBase, sid, baseDecimals, underlyingDecimals, onChain.address]);

    React.useEffect(() => {
        (async () => {
            const id = await onChain.cScholesOption.getOpposite(await cOrderBook.longOptionId()); // Get the Short Option ID
            setSid(id);
            const b = new ethers.Contract(await onChain.cScholesOption.getBaseToken(id), aIERC20Metadata.abi, onChain.signer);
            setCBase(b);
            const u = new ethers.Contract(await onChain.cScholesOption.getUnderlyingToken(id), aIERC20Metadata.abi, onChain.signer);
            setCUnderlying(u);
            setBaseSymbol(await b.symbol());
            setUnderlyingSymbol(await u.symbol());
            setBaseDecimals(await b.decimals());
            setUnderlyingDecimals(await u.decimals());
        }) ();
    }, [cOrderBook, onChain.address]);

    const assureAuthorized = async (cToken, amount) => {
        const allowance = await cToken.allowance(onChain.address, await onChain.cScholesCollateral.getAddress());
        if (allowance < amount) {
            try{
                const tx = await cToken.approve(await onChain.cScholesCollateral.getAddress(), amount)
                const r = await tx.wait()
                window.alert('Completed. Block hash: ' + r.blockHash);
             } catch(e) {
                window.alert(e.message + "\n" + (e.data?e.data.message:""))
                return false
            }
        }
        return true
    }

    const deposit = async () => {
        try{
            const bAmt = ethers.parseUnits(baseAmount, baseDecimals)
            const uAmt = ethers.parseUnits(underlyingAmount, underlyingDecimals)
            if (!await assureAuthorized(cBase, bAmt)) return;
            if (!await assureAuthorized(cUnderlying, uAmt)) return;
            const tx = await onChain.cScholesCollateral.deposit(sid, bAmt, uAmt)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const withdraw = async () => {
        try{
            const bAmt = ethers.parseUnits(baseAmount, baseDecimals)
            const uAmt = ethers.parseUnits(underlyingAmount, underlyingDecimals)
            const tx = await onChain.cScholesCollateral.withdraw(sid, bAmt, uAmt)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
         } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    React.useEffect(() => {
        // Listening for TransferSingle event
        const event = onChain.cScholesCollateral.filters.TransferSingle(); // Define event filter
        const listener = onChain.cScholesCollateral.on(event, async _ => {
            await refreshBalances()
        });

        // Clean up the effect
        return () => {
            onChain.cScholesCollateral.off(event, listener);
        };
    }, [onChain.address, cUnderlying, cBase, sid, baseDecimals, underlyingDecimals]);

    React.useEffect(() => {
        // Listening for TransferBatch event
        const event = onChain.cScholesCollateral.filters.TransferBatch(); // Define event filter
        const listener = onChain.cScholesCollateral.on(event, async _ => {
            await refreshBalances()
        });

        // Clean up the effect
        return () => {
            onChain.cScholesCollateral.off(event, listener);
        };
    }, [onChain.address, cUnderlying, cBase, sid, baseDecimals, underlyingDecimals]);

    React.useEffect(() => {
        if (!cBase) return;

        // Listening for Transfer event
        const event = cBase.filters.Transfer(); // Define event filter
        const listener = cBase.on(event, async (_) => {
            await refreshBalances()
        });

        // Clean up the effect
        return () => {
            cBase.off(event, listener);
        };
    }, [onChain.address, cUnderlying, cBase, sid, baseDecimals, underlyingDecimals]);

    React.useEffect(() => {
        if (!cUnderlying) return;

        // Listening for Transfer event
        const event = cUnderlying.filters.Transfer(); // Define event filter
        const listener = cUnderlying.on(event, async (_) => {
            await refreshBalances()
        });

        // Clean up the effect
        return () => {
            cUnderlying.off(event, listener);
        };
    }, [onChain.address, cUnderlying, cBase, sid, baseDecimals, underlyingDecimals]);

    return (<Box bg='gray.700' borderRadius='md' shadow='lg' p={2}>
        <SimpleGrid columns={4} spacing={1}>
        <Box bg='black' ></Box>
        <Box bg='black' ><Text>{baseSymbol}</Text></Box>
        <Box bg='black' ><Text>{underlyingSymbol}</Text></Box>
        <Box bg='black' ></Box>

        <Box bg='black' ><Text>Balance:</Text></Box>
        <Box bg='black' ><Text>{baseBalance}</Text></Box>
        <Box bg='black' ><Text>{underlyingBalance}</Text></Box>
        <Box bg='black' ></Box>

        <Box bg='black' ><Text>Collateral:</Text></Box>
        <Box bg='black' ><Text>{baseCollateralBalance}</Text></Box>
        <Box bg='black' ><Text>{underlyingCollateralBalance}</Text></Box>
        <Box bg='black' ></Box>

        <Box bg='black' ></Box>
        <Box bg='black' >        
            <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setBaseAmount(valueAsString)} >
            <NumberInputField />
            <NumberInputStepper>
                <NumberIncrementStepper />
                <NumberDecrementStepper />
            </NumberInputStepper>
            </NumberInput>
        </Box>
        <Box bg='black' >            
            <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setUnderlyingAmount(valueAsString)} >
            <NumberInputField />
            <NumberInputStepper>
                <NumberIncrementStepper />
                <NumberDecrementStepper />
            </NumberInputStepper>
            </NumberInput>
        </Box>
        <Box bg='black' >
            <Button color='black' bg='green' onClick={deposit}>Deposit</Button> &nbsp;
            <Button color='black' bg='red' onClick={withdraw}>Withdraw</Button>
        </Box>
        </SimpleGrid>
    </Box>);
}

export default Collaterals;