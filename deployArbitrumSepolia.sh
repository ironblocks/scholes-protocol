#!/bin/sh

set -e

# Run anvil.sh in another shell before running this

# To load the variables in the .env file
. ./.env

# Create some test orders
export CREATE_TEST_ORDERS="no"

# To deploy and verify our contract
forge script script/DeployAnywhere.s.sol:Deploy --rpc-url $ARBITRUM_SEPOLIA_RPC --sender $SENDER --private-key $PRIVATE_KEY --broadcast -v

./push_artifacts.sh "DeployAnywhere.s.sol/421614"

# cd web
# npm run build