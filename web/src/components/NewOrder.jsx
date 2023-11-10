// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import OnChainContext from './OnChainContext'
import { Box, Text, NumberInput, NumberInputField, NumberInputStepper, NumberDecrementStepper, NumberIncrementStepper, Button } from '@chakra-ui/react'
import { ethers } from 'ethers'
import aIERC20Metadata from '../artifacts/IERC20Metadata.json'

function NewOrder({cOrderBook}) {
    const onChain = React.useContext(OnChainContext)
    const [sid, setSid] = React.useState(null)
    const [amount, setAmount] = React.useState("0")
    const [price, setPrice] = React.useState("0")
    const [expiration, setExpiration] = React.useState(1)
    const [collateralRequirement, setCollateralRequirement] = React.useState(null)
    const [baseDecimals, setBaseDecimals] = React.useState(null)
    const [baseSymbol, setBaseSymbol] = React.useState(null)
    const [cBase, setCBase] = React.useState(null)
    
    React.useEffect(() => {
        (async () => {
            const id = await onChain.cScholesOption.getOpposite(await cOrderBook.longOptionId())
            setSid(id)
            const cBase = new ethers.Contract(await onChain.cScholesOption.getBaseToken(id), aIERC20Metadata.abi, onChain.signer);
            setCBase(cBase)
            setBaseDecimals(await cBase.decimals())
            setBaseSymbol(await cBase.symbol())
        }) ();
    }, [cOrderBook]);

    const bid = async () => {
        try {
            const amt = ethers.parseUnits(amount, 18);
            const prc = ethers.parseUnits(price, 18);
            const exp = BigInt(Math.floor(Date.now()/1000 + expiration * 60 * 60));
            const tx = await cOrderBook.make(amt, prc, exp)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const offer = async () => {
        try {
            const amt = -ethers.parseUnits(amount, 18);
            const prc = ethers.parseUnits(price, 18);
            const exp = BigInt(Math.floor(Date.now()/1000 + expiration * 60 * 60));
            const tx = await cOrderBook.make(amt, prc, exp)
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const assureAuthorized = async (amount) => {
        const allowance = await cBase.allowance(onChain.address, await cOrderBook.getAddress());
        if (allowance < amount) {
            try{
                const tx = await cBase.approve(await cOrderBook.getAddress(), amount)
                const r = await tx.wait()
                window.alert('Completed. Block hash: ' + r.blockHash);
            } catch(e) {
                window.alert(e.message + "\n" + (e.data?e.data.message:""))
                return false
            }
        }
        return true
    }

    const buy = async () => {
        try {
            const amt = ethers.parseUnits(amount, 18);
            const prc = ethers.parseUnits(price, 18);
            const exp = BigInt(Math.floor(Date.now()/1000 + expiration * 60 * 60));
            // Discover available offers in the order book
            const numOrders = await cOrderBook.numOrders();
            // Loop through the order book offers and build a list of offers to take
            const offersInOrderBook = [];
            const offersToTake = [];
            let amountRemaining = amt;
            let authorizationAmountNeeded = 0n;
            for (let i = 0; i < numOrders.numOffers; i++) {
                const offer = await cOrderBook.offers(i);
                offersInOrderBook.push({id: i, amount: offer.amount, price: offer.price, expiration: offer.expiration, owner: offer.owner});
            }
            // Now offersInOrderBook is a list of all offers in the order book.
            // Sort offersInOrderBook by price ascending - we want to take the lowest price offers first.
            offersInOrderBook.sort((a, b) => {
                if (a.price < b.price) return -1;
                if (a.price > b.price) return 1;
                return 0;
            });
            for (let i = 0; i < offersInOrderBook.length; i++) {
                const offer = offersInOrderBook[i];
                if (offer.price > prc) continue;
                if (offer.expiration < BigInt(Math.floor((Date.now()/1000)))) continue;
                if (offer.owner === onChain.address) continue;
                if (amountRemaining >= -offer.amount) {
                    offersToTake.push({id: offer.id, amount: -offer.amount, price: offer.price});
                    authorizationAmountNeeded += -offer.amount * offer.price / 10n**18n;
                    amountRemaining -= -offer.amount; // - - for clarity; compiler will optimize
                    if (amountRemaining === 0n) break;
                } else {
                    offersToTake.push({id: offer.id, amount: amountRemaining, price: offer.price});
                    authorizationAmountNeeded += amountRemaining * offer.price / 10n**18n;
                    amountRemaining = 0n;
                    break;
                }
            }
            // Now offersToTake is a list of offers to take.
            // Sort offersToTake by index descending - this makes sure the contract will not mutate the order IDs as it removes offers.
            // Note: this is correct, but not necessary fair to the makers, with respect to the order arrivals.
            offersToTake.sort((a, b) => {
                if (a.id < b.id) return 1;
                if (a.id > b.id) return -1;
                return 0;
            });
            let toBid;
            if (amountRemaining > 0n) {
                toBid = {amount: amountRemaining, price: prc, expiration: exp};
                authorizationAmountNeeded += amountRemaining * prc / 10n**18n;
            } else {
                toBid = {amount: 0n, price: 0n, expiration: 0n};
            }
            // Convert authorizationAmountNeeded to base token
            authorizationAmountNeeded = authorizationAmountNeeded * 10n**baseDecimals / 10n**18n;
            if (!await assureAuthorized(authorizationAmountNeeded)) return;
            const tx = await cOrderBook.sweepAndMake(true, offersToTake, toBid);
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    const sell = async () => {
        if (!window.confirm("This action will decrease your collateralization level,\n" +
                     "which may result in your position being closer to being liquidated.\n" +
                     "Please make sure you understand the risks before proceeding.\n" +
                     "Otherwise reject this transaction.")) return;
        try {
            const amt = ethers.parseUnits(amount, 18);
            const prc = ethers.parseUnits(price, 18);
            const exp = BigInt(Math.floor(Date.now()/1000 + expiration * 60 * 60));
            // Discover available bids in the order book
            const numOrders = await cOrderBook.numOrders();
            // Loop through the order book bids and build a list of bids to take
            const bidsInOrderBook = [];
            const bidsToTake = [];
            let amountRemaining = amt;
            for (let i = 0; i < numOrders.numBids; i++) {
                const bid = await cOrderBook.bids(i);
                bidsInOrderBook.push({id: i, amount: bid.amount, price: bid.price, expiration: bid.expiration, owner: bid.owner});
            }
            // Now bidsInOrderBook is a list of all bids in the order book.
            // Sort bidsInOrderBook by price descending - we want to take the highest price bids first.
            bidsInOrderBook.sort((a, b) => {
                if (a.price < b.price) return 1;
                if (a.price > b.price) return -1;
                return 0;
            });
            for (let i = 0; i < bidsInOrderBook.length; i++) {
                const bid = bidsInOrderBook[i];
                if (bid.price < prc) continue;
                if (bid.expiration < BigInt(Math.floor((Date.now()/1000)))) continue;
                if (bid.owner === onChain.address) continue;
                if (amountRemaining >= bid.amount) {
                    bidsToTake.push({id: bid.id, amount: -bid.amount, price: bid.price});
                    amountRemaining -= bid.amount;
                    if (amountRemaining === 0n) break;
                } else {
                    bidsToTake.push({id: bid.id, amount: -amountRemaining, price: bid.price});
                    amountRemaining = 0n;
                    break;
                }
            }
            // Now offersToTake is a list of offers to take.
            // Sort offersToTake by index descending - this makes sure the contract will not mutate the order IDs as it removes offers.
            // Note: this is correct, but not necessary fair to the makers, with respect to the order arrivals.
            bidsToTake.sort((a, b) => {
                if (a.id < b.id) return 1;
                if (a.id > b.id) return -1;
                return 0;
            });
            let toOffer;
            if (amountRemaining > 0n) {
                toOffer = {amount: -amountRemaining, price: prc, expiration: exp};
            } else {
                toOffer = {amount: 0n, price: 0n, expiration: 0n};
            }
            const tx = await cOrderBook.sweepAndMake(false, bidsToTake, toOffer);
            const r = await tx.wait()
            window.alert('Completed. Block hash: ' + r.blockHash);
        } catch(e) {
            window.alert(e.message + "\n" + (e.data?e.data.message:""))
        }
    }

    React.useEffect(() => {
        if (!sid) return;
        (async () => {
            const req = await onChain.cScholesOption.collateralRequirement(ethers.parseUnits(amount, 18), sid, true)
            setCollateralRequirement(ethers.formatUnits(req, baseDecimals))
        }) ();
    }, [cOrderBook, amount, price, onChain.address])

    return (<Box bg='gray.700' borderRadius='md' shadow='lg' p={2} >
        <Text>Amount:</Text>
        <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setAmount(valueAsString)} >
        <NumberInputField />
        <NumberInputStepper>
            <NumberIncrementStepper />
            <NumberDecrementStepper />
        </NumberInputStepper>
        </NumberInput>
        <Text>Price:</Text>
        <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setPrice(valueAsString)} >
        <NumberInputField />
        <NumberInputStepper>
            <NumberIncrementStepper />
            <NumberDecrementStepper />
        </NumberInputStepper>
        </NumberInput>
        <Text>Expiration (hours):</Text>
        <NumberInput defaultValue={0} min={0} precision={2} step={1} onChange={(valueAsString, valueAsNumber) => setExpiration(valueAsNumber)} >
        <NumberInputField />
        <NumberInputStepper>
            <NumberIncrementStepper />
            <NumberDecrementStepper />
        </NumberInputStepper>
        </NumberInput>
        <br/>
        <Button color='black' bg='green' onClick={bid}>Bid</Button> &nbsp;
        <Button color='black' bg='green' onClick={buy}>Buy</Button> &nbsp;
        <Button color='black' bg='red' onClick={offer}>Offer</Button> &nbsp;
        <Button color='black' bg='red' onClick={sell}>Sell/Write</Button> &nbsp;
        <Text>Collateral needed: {collateralRequirement} {baseSymbol} equivalent.</Text>
    </Box>);
}

export default NewOrder;