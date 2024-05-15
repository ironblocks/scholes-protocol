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

    IOrderBook public ob;
    IScholesOption public options;
    IScholesCollateral collaterals;
    uint256 longOptionId;
    uint256 shortOptionId;
    IERC20Metadata USDC;
    IERC20Metadata WETH;
    ISpotPriceOracle oracle;
    ITimeOracle mockTimeOracle;

    function setUpBase() internal {
        console.log("Creator (owner): ", msg.sender);

        // Test USDC token
        USDC = IERC20Metadata(address(new MockERC20("Test USDC", "USDC", 6, 10 ** 6 * 10 ** 6))); // 1M total supply
        console.log("Test USDC address: ", address(USDC));
        USDC.transfer(account1, 100000 * 10 ** USDC.decimals());
        USDC.transfer(account2, 100000 * 10 ** USDC.decimals());
        USDC.transfer(account3, 100000 * 10 ** USDC.decimals());

        // Test WETH token
        WETH = IERC20Metadata(address(new MockERC20("Test WETH", "WETH", 18, 10 ** 3 * 10 ** 18))); // 1M total supply
        console.log("Test WETH address: ", address(WETH));
        WETH.transfer(account1, 100 * 10 ** WETH.decimals());
        WETH.transfer(account2, 100 * 10 ** WETH.decimals());
        WETH.transfer(account3, 100 * 10 ** WETH.decimals());

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

        ISpotPriceOracle oracleEthUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd), WETH, USDC, false);
        console.log("WETH/USDC SpotPriceOracle based on ETH/USD deployed: ", address(oracleEthUsd));
        oracleList.addOracle(oracleEthUsd);

        TOptionParams memory optEthUsd;
        optEthUsd.underlying = WETH;
        optEthUsd.base = USDC;
        optEthUsd.strike = 2000 * 10 ** oracleEthUsd.decimals();
        optEthUsd.expiration = block.timestamp + 30 * 24 * 60 * 60; // 30 days from now
        optEthUsd.isCall = true;
        optEthUsd.isAmerican = false;
        optEthUsd.isLong = true;

        // TCollateralRequirements memory colreq;
        // colreq.entryCollateralRequirement = 2 ether / 10; // 0.2
        // colreq.maintenanceCollateralRequirement = 1 ether / 10; // 0.1

        obList.createScholesOptionPair(optEthUsd);

        ob = obList.getOrderBook(0); // The above WETH/USDC option
        console.log("WETH/USDC order book: ", address(ob));
        longOptionId = ob.longOptionId();
        shortOptionId = options.getOpposite(longOptionId);
        console.log("Long Option Id:", longOptionId);
        options.setCollateralRequirements(shortOptionId, 0, 0, options.timeOracle().getTime(), ""); // No collateral requirements (this is dangerous!!!)
        require(
            keccak256("WETH") == keccak256(abi.encodePacked(options.getUnderlyingToken(longOptionId).symbol())),
            "WETH symbol mismatch"
        ); // Check
        require(optEthUsd.expiration == options.getExpiration(longOptionId), "Expiration mismatch"); // Double-check
        oracle = options.spotPriceOracle(longOptionId);

        vm.startPrank(account1, account1);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);

        vm.startPrank(account2, account2);
        USDC.approve(address(collaterals), type(uint256).max);
        WETH.approve(address(collaterals), type(uint256).max);
    }
}
