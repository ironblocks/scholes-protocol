// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers'
import OnChainContext from './OnChainContext'
import { Button, ButtonGroup } from '@chakra-ui/react'
import aIERC20Metadata from '../artifacts/IERC20Metadata.json'
import aOrderBook from '../artifacts/OrderBook.json'

function OptionPicker({setObIndex}) {
    const onChain = React.useContext(OnChainContext)
    const [optionList, setOptionList] = React.useState([]);

    const ierc20Symbol = async (addr) => {
        const cIerc20 = new ethers.Contract(addr, aIERC20Metadata.abi, onChain.signer);
        return await cIerc20.symbol();
    }

    const formatName = (underlying, base, isCall, strike, expiration) => {
        let name = underlying + '/' + base;
        name += isCall ? '-C' : '-P';
        name += ethers.formatEther(strike);
        const e = new Date(Number(expiration) * 1000);
        let month = (e.getMonth() + 1).toString().padStart(2, '0'); // getMonth() returns a zero-based value (0-11)
        let day = e.getDate().toString().padStart(2, '0'); // getDate() returns the day of the month (1-31)
        name += '-' + month + day;
        return name;
    }

    const getOptionName = async (index) => {
        const obAddr = await onChain.cOrderBookList.getOrderBook(index);
        const cOrderBook = new ethers.Contract(obAddr, aOrderBook.abi, onChain.signer);
        const id = await cOrderBook.longOptionId();
        const underlying = await ierc20Symbol(await onChain.cScholesOption.getUnderlyingToken(id));
        const base = await ierc20Symbol(await onChain.cScholesOption.getBaseToken(id));
        const isCall = await onChain.cScholesOption.isCall(id);
        const strike = await onChain.cScholesOption.getStrike(id);
        const expiration = await onChain.cScholesOption.getExpiration(id);
        return formatName(underlying, base, isCall, strike, expiration)
    }

    React.useEffect(() => {
        (async () => {
            const n = (await onChain.cOrderBookList.getLength());
            let l = [];
            for (let i=0; i<n; i++) {
                l.push(getOptionName(i));
            } 
            setOptionList(l);
        }) ();
    }, [onChain.signer]); // On load

    return (<ButtonGroup gap='4' flexDirection='column' alignItems='center' margin={1}>
        <br/>
        {optionList.map((name, index) => <Button key={index} colorScheme='purple' size='sm' width='90%' align='center' onClick={()=>setObIndex(index)}>{name}</Button>)}
    </ButtonGroup>);
}

export default OptionPicker;