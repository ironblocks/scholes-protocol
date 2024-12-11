#!/bin/sh
set -e

# Load environment variables
source .env

# Don't create test orders for initial deployment
export CREATE_TEST_ORDERS="no"

# Deploy contracts
forge script script/DeployAnywhere.s.sol:Deploy \
    --rpc-url $HOLESKY_RPC \
    --broadcast \
    --verify \
    --sender $SENDER \
    --private-key $PRIVATE_KEY

# Save deployment artifacts
./push_artifacts.sh "DeployAnywhere.s.sol/17000"