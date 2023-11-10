# Development environment

## What's used for development

The contracts are developed in [Solidity](https://docs.soliditylang.org/en/v0.8.20/contracts.html) (version 8.x) and the [Foundry](https://github.com/foundry-rs) platform is used for building and testing. Any Unix environment would be good, including Ubuntu, MacOS or Windows WSL. The author uses the latest MacOS, but that is only a personal convenience choice and not a suggestion.

The front end is using JavaScript (Node.js v18.16.0 at the moment of writing this) and Reactm with [Chakra](https://chakra-ui.com/getting-started) for styling and it is running on [Next.js](https://nextjs.org).

## Installation

### Tools

- Install Foundry using the following [instructions](https://book.getfoundry.sh/getting-started/installation).
- Install [MetaMask](https://metamask.io/download/) on a Chrome-compatible browser.
- Install jq using ```brew install jq```

### Project setup

- Pull the project from the GitHub repository:
```
git clone git@github.com:scholesdev/protocol.git
```
- Copy the file .env.example to .env and modify it as appropriate:
```
cd protocol
cp .env.example .env
```
- Install the dependency libraries for the front end using the PNPM package manager:
```
cd web
pnpm install
```

### Running the development environment with the front end

- In the root of the project run a forked development node (leave it running):
```
./anvil.sh
```
- In another shell run the installation of the contracts:
```
./deployAnvil.sh
```
- After the contracts are installed (in the same shell if you like), run the front end development service:
```
pnpm dev
```
- Access the front end at ```http://localhost:3000```. Sign up using MetaMask. For convenience, use the same passphrase as in the ```.env``` file to to create test accounts in MetaMask, as they are funded with test AETH (Arbitrum Görli testnet Ethereum) and WETH and USDC tokens.

### Contract unit tests

To run the contract unit tests, the local foked Arbitrum node has to run, as it is using the Chainlink oracle. 
- Run the node (leave it running):
```
./anvil.sh
```
- Run the unit tests:
```
./test.sh
```

### Contract debugging

To debug the contracts, edit the function ```testBad()``` in the file ```test/Trading.t.sol``` and put the unit test of the problematic code.
Then run the node (leave it running):
```
./anvil.sh
```
- Run the problematic unit test:
```
./testBad.sh
```
- To step through the EVM code in the Foundry debugger run:
```
./debug.sh
```
