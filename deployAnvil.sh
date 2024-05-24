#!/bin/sh

set -e

# Run anvil.sh in another shell before running this

# To load the variables in the .env file
. ./.env

# Create some test orders
export CREATE_TEST_ORDERS="yes"

# To deploy and verify our contract
forge script script/DeployAnywhere.s.sol:Deploy --rpc-url "http://127.0.0.1:8545/" --sender $SENDER --private-key $PRIVATE_KEY --broadcast -v

./push_artifacts.sh "DeployAnywhere.s.sol/11155111"

# cd web
# npm run build