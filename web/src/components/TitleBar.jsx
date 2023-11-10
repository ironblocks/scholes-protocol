// SPDX-License-Identifier: BUSL-1.1
import React from 'react';
import { ethers } from 'ethers';
import { Flex, HStack, Button, Text } from '@chakra-ui/react'

function TitleBar({setSigner, address, setAddress}) {
    const [isConnected, setIsConnected] = React.useState(false);
    const [chainId, setChainId] = React.useState(null);

    React.useEffect(() => {
        // Check if MetaMask is installed
        if (typeof window.ethereum !== 'undefined') {
          // Listen for connect/disconnect events
          window.ethereum.on('accountsChanged', handleAccountsChanged);
          window.ethereum.on('disconnect', handleDisconnect);
          window.ethereum.on('chainChanged', handleChainChanged);

          // Check if already connected
          if (window.ethereum.selectedAddress) {
            setAddress(window.ethereum.selectedAddress);
            setIsConnected(true);
          }
        }
    }, []);

    const handleChainChanged = async _chainId => {
        // Handle chain change
        // setChainId(_chainId);
        await handleConnect();
    };

    const handleConnect = async () => {
        try {
            // Request account access
            await window.ethereum.request({ method: 'eth_requestAccounts' });

            // Get the connected address
            const provider = new ethers.BrowserProvider(window.ethereum);
            const signer = await provider.getSigner();
            setSigner(signer);
            const connectedAddress = await signer.getAddress();

            setAddress(connectedAddress);
            setChainId((await provider.getNetwork()).chainId);
            setIsConnected(true);
        } catch (error) {
            console.error(error);
        }
    };

    const handleDisconnect = () => {
        setAddress(null);
        setIsConnected(false);
        setSigner(null);
        setChainId(null);
    };

    React.useEffect(() => { // When page is started or refreshed
        handleDisconnect(); // Flush prior connection
    }, []);

    const handleAccountsChanged = async accounts => {
        if (accounts.length === 0) {
            handleDisconnect();
        } else {
            //setAddress(accounts[0]);
            //setIsConnected(true);
            await handleConnect();
        }
    };

    return (
        <Flex bg='gray.700' width='100%' justify='space-between' borderRadius='md' shadow='lg' align='center' p={2}>
            <Text fontWeight='bold'>Scholes</Text>
            <HStack>
                <Text>{address && <span>Address: {address}</span>} { chainId && "Chain Id: " + parseInt(chainId, 16) }</Text>
                {isConnected ? (
                    <Button colorScheme='purple' size='sm' onClick={handleDisconnect}>Disconnect</Button>
                ) : (
                    <Button  colorScheme='pink' size='sm' onClick={handleConnect}>Connect</Button>
                )}
            </HStack>
        </Flex>
      );
}

export default TitleBar;
