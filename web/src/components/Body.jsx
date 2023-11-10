// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { Grid, GridItem } from '@chakra-ui/react'
import OptionPicker from './OptionPicker'
import OptionTrading from './OptionTrading'
import OnChainContext from './OnChainContext'
import { ethers } from 'ethers'
import aScholesOption from '../artifacts/ScholesOption.json'
import aScholesCollateral from '../artifacts/IScholesCollateral.json'
import aSpotPriceOracleApprovedList from '../artifacts/ISpotPriceOracleApprovedList.json'
import aOrderBookList from '../artifacts/IOrderBookList.json'

function Body({ signer, address }) {
    const [onChainInfo, setOnChainInfo] = React.useState({});
    const [obIndex, setObIndex] = React.useState(null);

    React.useEffect(() => {
        if (!signer) return;
        (async () => {
            const cScholesOption = new ethers.Contract(aScholesOption.contractAddress, aScholesOption.abi, signer);
            const cScholesCollateral = new ethers.Contract(await cScholesOption.collaterals(), aScholesCollateral.abi, signer);
            const cSpotPriceOracleApprovedList = new ethers.Contract(await cScholesOption.spotPriceOracleApprovedList(), aSpotPriceOracleApprovedList.abi, signer);
            const cOrderBookList = new ethers.Contract(await cScholesOption.orderBookList(), aOrderBookList.abi, signer);
            setOnChainInfo({signer: signer, address: address, cScholesOption: cScholesOption, cScholesCollateral: cScholesCollateral, cSpotPriceOracleApprovedList: cSpotPriceOracleApprovedList, cOrderBookList: cOrderBookList });
        }) ();
    }, [signer, address]);

    if (!signer) return(<><br/>Please connect!</>)
    if (!onChainInfo.cScholesOption) return("Please wait...")
    return (<OnChainContext.Provider value={onChainInfo} >
        <Grid width='100%'>
            <GridItem rowStart={1} colSpan={1}  bg='black'>
                <OptionPicker setObIndex={setObIndex}/>
            </GridItem>
            <GridItem rowStart={1} colSpan={19}  bg='black'>
                <OptionTrading obIndex={obIndex} />
            </GridItem>
        </Grid>
    </OnChainContext.Provider>);
}

export default Body;