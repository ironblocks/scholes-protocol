#!/bin/sh
# Run anvil.sh in another shell before running this

. ./.env

# To deploy and verify our contract - needs a forked environment because of the oracle
forge test --rpc-url "http://127.0.0.1:8545/" -vvv
