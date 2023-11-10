#!/bin/zsh

# Run anvil.sh in another shell before running this

# To load the variables in the .env file
source .env

# To deploy and verify our contract
forge script script/DeployArbitrumGorli.s.sol:Deploy --rpc-url "https://goerli-rollup.arbitrum.io/rpc" --sender $SENDER --private-key $PRIVATE_KEY --broadcast -v

source push_artifacts.sh "DeployArbitrumGorli.s.sol/421613"

# cd web
# npm run build