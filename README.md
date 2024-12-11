# Venn x Scholes Integration

This repository contains the integration between Venn Protocol and Scholes, including modified contracts, deployment scripts, and examples of how to use the Venn firewall with Scholes.

## 📝 Deployed Contracts

### Core Contracts
| Contract Name | Network | Address |
|--------------|---------|----------|
| SCH Token    | Holesky | [`0xd4cd8c5c80Ae00cED999d078440445d7dd247E95`](https://holesky.etherscan.io/address/0xd4cd8c5c80Ae00cED999d078440445d7dd247E95) |
| ScholesOption| Holesky | [`0x30DC1F6C1b50c9118163504f09C165C891E760d5`](https://holesky.etherscan.io/address/0x30DC1F6C1b50c9118163504f09C165C891E760d5) |
| ScholesCollateral| Holesky | [`0xcF9660825e275dEFa91Fa8F344520125AA3d2734`](https://holesky.etherscan.io/address/0xcF9660825e275dEFa91Fa8F344520125AA3d2734) |
| ScholesLiquidator| Holesky | [`0x6334af24CB62f82DE329549a53d164C744C97d33`](https://holesky.etherscan.io/address/0x6334af24CB62f82DE329549a53d164C744C97d33) |

### Oracle & OrderBook Contracts
| Contract Name | Network | Address |
|--------------|---------|----------|
| SpotPriceOracleApprovedList| Holesky | [`0xADc4f3396DB316B5E2ccd223e8D11BeAefDF7076`](https://holesky.etherscan.io/address/0xADc4f3396DB316B5E2ccd223e8D11BeAefDF7076) |
| OrderBookList| Holesky | [`0xFD47E5730dEbdef732940241f80f1A38237dA62d`](https://holesky.etherscan.io/address/0xFD47E5730dEbdef732940241f80f1A38237dA62d) |
| MockTimeOracle| Holesky | [`0x3aFd5E4C52f9736F0EAe46dEe882158D9b3152dc`](https://holesky.etherscan.io/address/0x3aFd5E4C52f9736F0EAe46dEe882158D9b3152dc) |

### Test Tokens
| Contract Name | Network | Address |
|--------------|---------|----------|
| TestUSDC| Holesky | [`0x2EccD0AeA2317558F03c5758B19F7745f54EA1Ea`](https://holesky.etherscan.io/address/0x2EccD0AeA2317558F03c5758B19F7745f54EA1Ea) |
| TestWETH| Holesky | [`0x026bc390C753F280663472dB16d245156297CCa0`](https://holesky.etherscan.io/address/0x026bc390C753F280663472dB16d245156297CCa0) |
| TestWBTC| Holesky | [`0x0DA907e3e4E16585E20018fdAD40e8cd49e6D79b`](https://holesky.etherscan.io/address/0x0DA907e3e4E16585E20018fdAD40e8cd49e6D79b) |

### Price Oracles & OrderBooks
| Contract Name | Network | Address |
|--------------|---------|----------|
| SCH/USDC SpotPriceOracle| Holesky | [`0x932265559561A66d1E8F9f5eB011083BB4acaB50`](https://holesky.etherscan.io/address/0x932265559561A66d1E8F9f5eB011083BB4acaB50) |
| WETH/USDC SpotPriceOracle| Holesky | [`0x0994D6C79ABeb7042365F4c3E98Ed72C72764FF4`](https://holesky.etherscan.io/address/0x0994D6C79ABeb7042365F4c3E98Ed72C72764FF4) |
| WBTC/USDC SpotPriceOracle| Holesky | [`0xe0B04Bea3a0c97012e9a7d9EC71c2aACF072e191`](https://holesky.etherscan.io/address/0xe0B04Bea3a0c97012e9a7d9EC71c2aACF072e191) |
| WETH/USDC OrderBook| Holesky | [`0x4661450F8C83274be7cBeBD7dC4489E27D3e085D`](https://holesky.etherscan.io/address/0x4661450F8C83274be7cBeBD7dC4489E27D3e085D) |

## 🔧 Modified Contracts

The following contracts have been modified to support the Venn x Scholes integration:

### Core Protocol
- `ScholesOption.sol`
- `ScholesCollateral.sol`
- `ScholesLiquidator.sol`
- `StSCH.sol`

### Oracle & OrderBook System
- `OrderBook.sol`
- `OrderBookList.sol`
- `SpotPriceOracle.sol`
- `SpotPriceOracleApprovedList.sol`

### Test Contracts
- `MockERC20.sol`
- `MockTimeOracle.sol`

## 🔍 Example Transactions

### Sample Transactions on Holesky
1. [Transaction 1](https://holesky.etherscan.io/tx/0xe21f061e75ef946eb7a017a273d741050f8b4daa4a11758cd8a6a6299aabd7fb)
2. [Transaction 2](https://holesky.etherscan.io/tx/0x6c24ff9c704033fcc68a4d6ef453d7f2e5326af6f8c732a8221cd6327744b12a)

## 📜 Venn Scripts

The integration scripts are located in `venn-scripts`. These scripts utilize the Venn SDK to interact with the deployed contracts and demonstrate the integration functionality.

## 🚀 How To Deploy and Run the Venn Firewall Integration

To deploy, run:

```bash
./deployHolesky.sh
```

Check the docs at [Venn Network Installation Guide](https://docs.venn.build/venn-network/getting-started/protocols-and-developers/installation).

Please note, these contracts have already been modified, so proceed from step 3.