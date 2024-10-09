// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/OrderBookList.sol";
import "../src/ScholesOption.sol";
import "../src/ScholesCollateral.sol";
import "../src/ScholesLiquidator.sol";
import "../src/SpotPriceOracleApprovedList.sol";
import "../src/SpotPriceOracle.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../src/types/TOptionParams.sol";
import "../src/types/TCollateralRequirements.sol";
import "../src/types/TSweepOrderParams.sol";
import "../src/MockERC20.sol";
import "../src/MockTimeOracle.sol";
import "../src/interfaces/ISpotPriceOracle.sol";

contract BaseTest is Test {
    // Test accounts from passphrase in env (not in repo)
    address constant account0 = 0x1FE2BD1249b9dC89F497052630d393657E62d36a;
    address constant account1 = 0xAA1AD0696F3f970eE4619DD646C12600b003b1b5;
    address constant account2 = 0x264F92eac76DA3244EDc7dD89eC3c7AcC719BE2a;
    address constant account3 = 0x4eBBf92803dfb004b543d4DB592D9C32C0a830A9;

    address constant chainlinkEthUsd = 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08; // on Arbitrum Görli
    // address constant chainlinkEthUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // on Arbitrum One Mainnet

    IOrderBook public callDC2000OrderBook; // call, dual collateral, 2000
    IOrderBook public putDC2000OrderBook; // put, dual collateral, 2000
    IOrderBook public callSC3000OrderBook; // call, single collateral, 3000
    IOrderBook public putSC3000OrderBook; // put, single collateral, 3000
    IScholesOption public options;
    IScholesCollateral collaterals;
    IERC20Metadata USDC;
    IERC20Metadata WETH;
    ISpotPriceOracle oracleEthUsd;
    ITimeOracle mockTimeOracle;
    TOptionParams optEthUsdCallDC2000; // call, dual collateral, 2000
    TOptionParams optEthUsdPutDC2000; // put, dual collateral, 2000
    TOptionParams optEthUsdCallSC3000; // call, single collateral, 3000
    TOptionParams optEthUsdPutSC3000; // put, single collateral, 3000
    uint256 oneHourExpiration;
    uint256 INITIAL_USDC_BALANCE = 100000; // 100K
    uint256 INITIAL_WETH_BALANCE = 100;

    function setUp() public virtual {
        console.log("Creator (owner): ", msg.sender);

        // Test USDC token
        USDC = IERC20Metadata(address(new MockERC20("Test USDC", "USDC", 6, 10 ** 6 * 10 ** 6))); // 1M total supply
        console.log("Test USDC address: ", address(USDC));
        USDC.transfer(account1, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        USDC.transfer(account2, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());
        USDC.transfer(account3, INITIAL_USDC_BALANCE * 10 ** USDC.decimals());

        // Test WETH token
        WETH = IERC20Metadata(address(new MockERC20("Test WETH", "WETH", 18, 10 ** 3 * 10 ** 18))); // 1K total supply
        console.log("Test WETH address: ", address(WETH));
        WETH.transfer(account1, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        WETH.transfer(account2, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());
        WETH.transfer(account3, INITIAL_WETH_BALANCE * 10 ** WETH.decimals());

        // SCH token
        IERC20Metadata SCH = IERC20Metadata(address(new MockERC20("SCH", "SCH", 18, 10 ** 6 * 10 ** 18))); // 1M total supply
        console.log("SCH token address: ", address(SCH));

        options = new ScholesOption();
        console.log("ScholesOption deployed: ", address(options));

        collaterals = new ScholesCollateral(address(options));
        console.log("ScholesCollateral deployed: ", address(collaterals));

        IScholesLiquidator liquidator = new ScholesLiquidator(address(options));
        console.log("ScholesLiquidator deployed: ", address(liquidator));
        SCH.transfer(address(liquidator), 100000 * 10 ** SCH.decimals()); // Fund the backstop stake with 100000 SCH - move this into the tests

        ISpotPriceOracleApprovedList oracleList = new SpotPriceOracleApprovedList();
        console.log("SpotPriceOracleApprovedList deployed: ", address(oracleList));

        IOrderBookList obList = new OrderBookList(options);
        console.log("OrderBookList deployed: ", address(obList));

        mockTimeOracle = new MockTimeOracle();
        console.log("MockTimeOracle deployed: ", address(mockTimeOracle));
        oneHourExpiration = mockTimeOracle.getTime() + 1 hours;

        options.setFriendContracts(
            address(collaterals),
            address(liquidator),
            address(oracleList),
            address(obList),
            address(mockTimeOracle),
            address(SCH)
        );
        collaterals.setFriendContracts();
        liquidator.setFriendContracts();
        // In order for the liquidation backstop to work, the liquidator must be funded with SCH, by staking using liquidator.stSCH().stake()

        // Mock SCH/USDC oracle
        ISpotPriceOracle oracleSchUsd =
            new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd /*Irrelevant-always mock*/ ), SCH, USDC, false);
        oracleSchUsd.setMockPrice(1 * 10 ** oracleSchUsd.decimals()); // 1 SCH = 1 USDC
        console.log("SCH/USDC SpotPriceOracle based on ETH/USD deployed, but always mocked: ", address(oracleSchUsd));
        oracleList.addOracle(oracleSchUsd);

        oracleEthUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd), WETH, USDC, false);
        console.log("WETH/USDC SpotPriceOracle based on ETH/USD deployed: ", address(oracleEthUsd));
        oracleList.addOracle(oracleEthUsd);

        // Call, dual collateral
        optEthUsdCallDC2000.underlying = WETH;
        optEthUsdCallDC2000.base = USDC;
        optEthUsdCallDC2000.strike = 2000 * 10 ** oracleEthUsd.decimals();
        optEthUsdCallDC2000.expiration = block.timestamp + 10 days;
        optEthUsdCallDC2000.isCall = true;
        optEthUsdCallDC2000.isAmerican = false;
        optEthUsdCallDC2000.isLong = true;
        optEthUsdCallDC2000.isSingleCollateral = false;

        // Put, dual collateral
        optEthUsdPutDC2000.underlying = WETH;
        optEthUsdPutDC2000.base = USDC;
        optEthUsdPutDC2000.strike = 2000 * 10 ** oracleEthUsd.decimals();
        optEthUsdPutDC2000.expiration = block.timestamp + 20 days;
        optEthUsdPutDC2000.isCall = false;
        optEthUsdPutDC2000.isAmerican = false;
        optEthUsdPutDC2000.isLong = true;
        optEthUsdPutDC2000.isSingleCollateral = false;

        // Call, single collateral
        optEthUsdCallSC3000.underlying = WETH;
        optEthUsdCallSC3000.base = USDC;
        optEthUsdCallSC3000.strike = 3000 * 10 ** oracleEthUsd.decimals();
        optEthUsdCallSC3000.expiration = block.timestamp + 30 days;
        optEthUsdCallSC3000.isCall = true;
        optEthUsdCallSC3000.isAmerican = false;
        optEthUsdCallSC3000.isLong = true;
        optEthUsdCallSC3000.isSingleCollateral = true;

        // Put, single collateral
        optEthUsdPutSC3000.underlying = WETH;
        optEthUsdPutSC3000.base = USDC;
        optEthUsdPutSC3000.strike = 3000 * 10 ** oracleEthUsd.decimals();
        optEthUsdPutSC3000.expiration = block.timestamp + 30 days;
        optEthUsdPutSC3000.isCall = false;
        optEthUsdPutSC3000.isAmerican = false;
        optEthUsdPutSC3000.isLong = true;
        optEthUsdPutSC3000.isSingleCollateral = true;

        // TCollateralRequirements memory colreq;
        // colreq.entryCollateralRequirement = 2 ether / 10; // 0.2
        // colreq.maintenanceCollateralRequirement = 1 ether / 10; // 0.1

        obList.createScholesOptionPair(optEthUsdCallDC2000);
        obList.createScholesOptionPair(optEthUsdPutDC2000);
        // needed for single collateral as we create the pair
        oracleEthUsd.setMockPrice(3000 * 10 ** oracleEthUsd.decimals());
        obList.createScholesOptionPair(optEthUsdCallSC3000);
        obList.createScholesOptionPair(optEthUsdPutSC3000);

        callDC2000OrderBook = obList.getOrderBook(0);
        putDC2000OrderBook = obList.getOrderBook(1);
        callSC3000OrderBook = obList.getOrderBook(2);
        putSC3000OrderBook = obList.getOrderBook(3);
        console.log("WETH/USDC order book: ", address(callDC2000OrderBook));
        console.log("Long Option Id:", callDC2000OrderBook.longOptionId());
        options.setCollateralRequirements(
            options.getOpposite(callDC2000OrderBook.longOptionId()), 0, 0, options.timeOracle().getTime(), ""
        ); // No collateral requirements (this is dangerous!!!)
        options.setCollateralRequirements(
            options.getOpposite(putDC2000OrderBook.longOptionId()), 0, 0, options.timeOracle().getTime(), ""
        ); // No collateral requirements (this is dangerous!!!)
        require(
            keccak256("WETH")
                == keccak256(abi.encodePacked(options.getUnderlyingToken(callDC2000OrderBook.longOptionId()).symbol())),
            "WETH symbol mismatch"
        ); // Check
        require(
            optEthUsdCallDC2000.expiration == options.getExpiration(callDC2000OrderBook.longOptionId()),
            "Expiration mismatch"
        ); // Double-check
        require(
            optEthUsdPutDC2000.expiration == options.getExpiration(putDC2000OrderBook.longOptionId()),
            "Expiration mismatch"
        ); // Double-check
        require(
            optEthUsdCallSC3000.expiration == options.getExpiration(callSC3000OrderBook.longOptionId()),
            "Expiration mismatch"
        ); // Double-check
        require(
            optEthUsdPutSC3000.expiration == options.getExpiration(putSC3000OrderBook.longOptionId()),
            "Expiration mismatch"
        ); // Double-check

        vm.startPrank(account1, account1);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);

        vm.startPrank(account2, account2);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);

        vm.startPrank(account3, account3);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);
        USDC.approve(address(callDC2000OrderBook), type(uint256).max);
        WETH.approve(address(callDC2000OrderBook), type(uint256).max);
    }

    /**
     * Helper function to assert the balance of a given ERC20 token for a specific account.
     * This function checks if the account's balance of the specified token matches the expected balance.
     *
     * @param token The ERC20 token to check the balance of.
     * @param _account The address of the account whose balance is to be checked.
     * @param _expectedBalance The expected balance of the account.
     */
    function assertBalanceOf(IERC20Metadata token, address _account, uint256 _expectedBalance) internal {
        uint256 balance = token.balanceOf(address(_account));
        assertEq(balance, _expectedBalance, "Balance mismatch");
    }

    /**
     * Helper function to assert collateral balances.
     * Ensures that the given account has the expected base and underlying balances.
     */
    function assertCollateralsBalances(
        IScholesCollateral _collaterals,
        address _account,
        uint256 _optionId,
        uint256 _expectedBaseBalance,
        uint256 _expectedUnderlyingBalance
    ) internal {
        (uint256 baseBalance, uint256 underlyingBalance) = _collaterals.balances(_account, _optionId);
        assertEq(baseBalance, _expectedBaseBalance, "Base balance mismatch");
        assertEq(underlyingBalance, _expectedUnderlyingBalance, "Underlying balance mismatch");
    }
}
