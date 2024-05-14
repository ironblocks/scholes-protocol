# Scholes Protocol

[![test](https://github.com/scholes-protocol/protocol/actions/workflows/test.yml/badge.svg)](https://github.com/scholes-protocol/protocol/actions/workflows/test.yml)

Scholes Options Protocol provides the following:
- Handles European and American style Options on ERC-20 assets. It manages their lifetime including collateralization, exercising and liquidation.
- Allows the users to transfer options' ownership, seamlessly enforcing collateralization.
- Transfers of non-existent options automatically results in immediate minting of such options as long as both parties meet the collateralization requirements.
- Provides a marketplace for trading those options,
- Coming soon: Allows third party options to be wrapped and traded as if they were natively issued. 

## Installation instructions

See [this](DEVENV.md) page for installation instructions of the development environment.

## Summary of the protocol architecture:

### Oracle

The protocol needs an oracle (price feed), which would be used mainly for liquidations. The oracle should be able to provide pricing of the underlying assets. Even though the options' premiums are determined by the market forces in the market place, the protocol calculates its own metrics used for the purpose of determining entry and liquidation collateralization levels. 

### Option Creation

Before even creating open interest by minting options, new options have to be created for each set in interest of the following:
- base and underlying asset pair, both ERC-20 tokens,
- option strike price, denominated in the ratio of underlying/base assets, such as "1800 WETH/USDC",
- option expiration date/time,
- option style, European or American. European style options can only be exercised upon expiration, while the American style options can be exercised by the (long) holder at any time.
- option kind, Call or Put. A Call (Put) option of quantity 1 is the right to purchase (sell) quantity 1 (as opposed to 100 in the traditional finance) of the underlying asset at the strike price, from the issuer (minter, underwriter, short) of the option.

In addition to the above, since the short option holders (underwriters) have to meet collateralization requirements a set of parameters needs to be added to the option upon creation. These are:
- Entry Collateral requirement factor. This determines the amount of required collateralization for any option writer to increase his (short; mint) position.
- Maintenance Collateral requirement factor. This determines the amount of collateral required for any short option holder to hold at any time to avoid being liquidated.
- Liquidation Penalty factor. This determines the liquidation penalty based on the amount of short holding at the time of eventual liquidation.

However, before an option is created there has to be a price oracle for the price (ratio) of the underlying/base tokens. If no such oracle is registered with the protocol, the option creation would fail.

Each option created with the above parameters lives as an ERC-1155 token with a specific pair of IDs, one for the short such option and one for the long one. The reason for having 2 ERC-1155 tokens/ids is because the ERC-1155 standard allows only for positive amount of holdings. So, for example, if an account with no prior option holdings mints 10 options (is now 10 short), this is reflected as 0 holding of the long option ID and holding of 10 of the short option ID. The implementation of the Scholes Option ERC-1155 contract enforces this duality, so any holder can have only one or the other of non-zero amount of holding, but never both.

### Order Book Creation

As the newly created option needs a marketplace, a new Order Book has to be created. The contract "OrderBookList" has a method "createScholesOptionPair" which creates the proper Option and Collateral tokens and the corresponding Order Book, which readies such option for immediate trading.

### Minting

Placing orders on the Order Book for a specific option does not transfer or create any options. It only indicates the intent of the market participant to buy or sell certain amount of the option for at a specific price (limit). The payout for the eventual transaction is the Premium.

Only when a buyer and seller meet each other's conditions the option changes hands in exchange for Premium payout. If such option exists, it is transferred, but if it does not, it's minted. Minting of an option does not cost. The only financial implication is that the underwriter (writer, seller) of the option has to commit an appropriate amount of collateral, in order to guarantee he can meet the obligation when the option is exercised (we use the term "exercise" even when the option expires), or at least to be able to be liquidated and pay the liquidation penalty.

For example, party A wants to buy 10 options of a certain kind. He places a bid at a certain price (Premium). Note that buying and option increases the long position, and holding long options does not require any collateral. On the other side of the order book, a seller takes this order by receiving the Premium payment and mints the short option position. This position can only be minted if the minter meets the entry collateralization level, and that collateral is locked. At the same time, a long option is minted and placed in the buyer's account, without the need for any collateralization. All of the above occurs atomically, meaning that it all succeeds or everything reverts to the previous state.

### Collateral Structure

In order to be able to wrap other protocols' options we have to allow for different ways to keep and enforce collateralization. Scholes options can be collateralized in both the underlying or the base asset denominations, as well as a combination of both. For example, an ETH/USDC short call option position can be collateralized by depositing ETH, USDC or both. Any transfer of ownership of that option would require that the receiver has to meet entry collateralization requirements. Furthermore, the position has to keep maintenance collateralization in order to avoid liquidation.

The call option allows the holder to purchase the underlying asset from the issuer (counterparty) at the strike price. In order for the issuer to be able to cater to such redemption, they have to keep in possession collateral in the amount of the option denominated in the underlying asset. Conversely, the same can be achieved by holding an equivalent amount of the base asset. By equivalent, it is meant an amount of base asset immediately exchangeable to the proper amount of the underlying asset at an available marketplace such as an order book or an AMM. If this call option is collateralized by the full amount of underlying asset, the option is ***covered***. An equivalent amount of the base asset does not guarantee such cover, as the price may change at any time and render the option not fully collateralized. Conversely, a put option can be covered by the full amount of base asset. 

The conversion price between the underlying and base assets is the price determined by the price oracle, as long as the settlement price has not been set (after expiration). Then, the settlement price is used for conversion.

If the user tries to withdraw collateral in underlying (base) denomination, and the protocol does not hold enough underlying (base) assets, the insufficient amount is paid out in base (underlying) denomination according to the above conversion rate. This situation can only occur after certain amount of options have been exercised and an appropriate amount of collateral is transferred as part of the exercise process. In case of European style options, this can only happen after the expiration of the option.

The protocol allows for partially collateralized options, which can become subject to liquidation. The oracle is used to add the collaterals in both denominations and convert them to a fraction of collateralization in underlying (base) asset for the call (put) options correspondingly. This fraction determines the ability to transact (for entry collateralization) and/or liquidate (for maintenance collateralization) the option.

Upon creation of each option ERC-1155 pair of tokens (for long and short positions), a pair of ERC-1155 collateral tokens is also created, one for the underlying and one for the base assets. The collateral cannot be held in the option holder's account as regular ERC-20 token, as the user can freely transfer it out and avoid meeting collateralization requirements. Instead, the user should deposit collateral in either or both the underlying and/or base assets into this ERC-1155 contract and receive an equal amount of ERC-1155 tokens for the ERC-20 tokens deposited. The user is free to deposit adn withdraw collateral as long as the deposited collateral at the end of the transaction meets the entry collateralization requirements for the short option position held. Even the Premium payment, trading fees, liquidation penalties/rewards, and exercise payouts go into these ERC-1155 collateral tokens. 

***TO BE DISCUSSED***: 
In addition to the above, some protocols allow for margin trading where the margin provider adds collateral for a fee in order to fully collateralize options. If the position (holder) falls below maintenance collateralization, the the margin provider would have the first right of liquidation of the option. At the same time, the holder should have freedom to trade the option. In such case, the option would be marked as "margin" and the address of the lienholder would be set to be the address of the margin provider. 

### Collateralization Requirements and Option Holding Transfers

There are two kinds of collateralization requirements: Entry and Maintenance. Upon every transfer of options, the party which increases its short position has to meet the Entry Collateralization Requirement, otherwise the corresponding transaction atomically fails. Maintenance Collateralization level has to be maintained at any time, in order to prevent being liquidated, which is costly.

This is how this collateralization is enforced:
- Anyone can permissionlessly check whether the Maintenance Collateralization level is met. If it is not, anyone can permissionlessly liquidate the corresponding position.
- In the entire protocol, the Entry collateral requirements are checked in a single place: upon transfer of option holdings. This is ***very specific to the Scholes protocol***. Minting and burning of options is also considered transfer from and to a null address. It does not matter what the previous position was, whether it was long short and what the amount was. The transfer is executed optimistically, and then the Entry collateralization is checked. Specifically, only if the short position is increased, the new short position at the end has to meet the Entry Collateralization requirement. Otherwise, the entire transaction fails, regardless if how it was initiated: it could have been a transfer of ownership, a trade, or minting of a new short option as a result of a trade. This makes the protocol security extremely simple and easy to audit and verify.

As prices change, each position has to replenish the collateral in order to keep the maintenance collateralization level. Otherwise, the position can be liquidated. 

### Counterparty risk

Option counterparty risk has to be unified across the entire order book. Otherwise, for any holder the value of the specific amount issued by specific issuer would also depend on the collateralization of the issuer. Traditional finance deals with this using counterparty risk insurance and credit guarantees. Still, runaway squeezes can occur.

### Liquidation

 Once a position falls below the maintenance collateralization level, it can be liquidated. The liquidator can take over the position and in addition charge a penalty against the liquidated holder's collateral. Anyone can be a liquidator. However, the liquidator has to meet the entry collateralization level in order to be able to complete the liquidation.

 If the position being liquidated does not have sufficient collateral to pay the liquidation penalty, the liquidation can still proceed. In such case, the liquidator would take whatever collateral is available as partial penalty.

### Insolvent positions

The liquidation can be performed so late that the liquidated position is insolvent, namely it does not have enough collateral to even cover the unrealized loss. In such case no liquidator would be interested in that position. As this situation is dangerous for the entire protocol, it must be dealt with by the protocol itself. The protocol has to perform the liquidation at a loss, and cover such loss by selling protocol tokens on the open market. To make sure such sale is possible, sufficient liquidity shall be deposited in an Automated Market Maker (AMM) such as Uniswap.

### Emergency shutdown

If the collateralization level of the entire protocol falls below a dangerous level the protocol can preform an ***emergency shutdown***. This level is decided by voting of the holders of the protocol token, but recorded in the protocol, so that any observer can initiate the emergency shutdown if the condition is met, in order to delay further damage. 

At the time of the emergency shutdown all positions are liquidated at the current premium prices and refunded in the collateral denomination. In addition the liquidated positions receive penalty, denominated in the protocol token. If no sufficient collateral exists, protocol tokens would be sold in exchange of collateral denominated assets, in order to complete the liquidations. If no such possibility exists, all protocol tokens are distributed to the liquidated positions, proportionally to their value.

After the emergency shutdown, the protocol restarts again from a clean slate. 

### Wrapped foreign options

The protocol can wrap options issued by other (foreign) protocols.

If the foreign protocols allow for undercollateralization, the wrapped versions may have to be re-collateralized in order to meet the requirements of the Scholes protocol. The wrapped options would have special functions for dealing with the collateralization, such as liquidations in the foreign protocols and locking of the collateral placed in the foreign protocols. This functionality is reserved for a future version.

If the foreign protocol only allows for covered options, than the above issue disappears. For example options issued in the protocol Premia.finance are always covered. An ETH/USDC call is always collateralized by the issuer (minter) in ETH, so that upon exercise, the purchased option would result in distribution of ETH. When wrapped in Scholes, such option upon exercise results in distribution of USDC by swapping on a specified AMM the distribution of ETH by the wrapped option. The user shall be aware of this process and the resulting excess profit or loss resulting for this swap.

### Fees and protocol token

The protocol charges fees for each transaction. These fees are denominated in the base collateral currency and accumulate in the corresponding smart contract. Upon request, these fees are distributed proportionally to the holders of the protocol token. 