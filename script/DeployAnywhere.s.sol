// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/OrderBookList.sol";
import "../src/ScholesOption.sol";
import "../src/ScholesLiquidator.sol";
import "../src/ScholesCollateral.sol";
import "../src/SpotPriceOracleApprovedList.sol";
import "../src/SpotPriceOracle.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../src/types/TOptionParams.sol";
import "../src/types/TCollateralRequirements.sol";
import "../src/MockERC20.sol";
import "../src/MockTimeOracle.sol";

contract Deploy is Script {
        
    // Test accounts from passphrase in env (not in repo)
    address constant account0 = 0x1FE2BD1249b9dC89F497052630d393657E62d36a;
    address constant account1 = 0xAA1AD0696F3f970eE4619DD646C12600b003b1b5;
    address constant account2 = 0x264F92eac76DA3244EDc7dD89eC3c7AcC719BE2a;
    address constant account3 = 0x4eBBf92803dfb004b543d4DB592D9C32C0a830A9;

    // Networks we are deploying to
    uint256 constant SEPOLIA_CHAINID = 11155111; // Sepolia

    uint256 constant ARBITRUM_ONE_CHAINID = 42161; // Arbitrum One Mainnet
    uint256 constant ARBITRUM_GORLI_CHAINID = 421613; // Arbitrum Görli - deprecated
    uint256 constant ARBITRUM_SEPOLIA_CHAINID = 421614; // Arbitrum Sepolia Testnet

    uint256 constant BASE_CHAINID = 8453; // Base Mainnet
    uint256 constant BASE_SEPOLIA_CHAINID = 84532; // Base Sepolia Testnet

    uint256 constant OP_CHAINID = 10; // Optimism Mainnet
    uint256 constant OP_SEPOLIA_CHAINID = 11155420; // Optimism Sepolia Testnet

    // Use https://www.unixtimestamp.com/ to get the timestamp for the expiration dates
    uint256 constant EXPIRATION_1 = 1714579200; // Wed May 01 2024 16:00:00 GMT+0000
    uint256 constant EXPIRATION_2 = 1706806800; // Thu Feb 01 2024 17:00:00 GMT+0000
    uint256 constant EXPIRATION_3 = 1709312400; // Fri Mar 01 2024 17:00:00 GMT+0000
    uint256 constant EXPIRATION_4 = 1711987200; // Mon Apr 01 2024 16:00:00 GMT+0000

    // Chainlink oracles
    address chainlinkEthUsd;
    address chainlinkBtcUsd;

    function init() internal {
        if (block.chainid == ARBITRUM_GORLI_CHAINID) {
            chainlinkEthUsd = 0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08;
            chainlinkBtcUsd = 0x6550bc2301936011c1334555e62A87705A81C12C;
        } else if (block.chainid == SEPOLIA_CHAINID) {
            chainlinkEthUsd = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
            chainlinkBtcUsd = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        } else if (block.chainid == ARBITRUM_SEPOLIA_CHAINID) {
            chainlinkEthUsd = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
            chainlinkBtcUsd = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
        } else if (block.chainid == BASE_CHAINID) {
            chainlinkEthUsd = 0x0000000000000000000000000000000000000000;
            chainlinkBtcUsd = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
            revert("No chainlink oracle for BTC/USD on Base yet");
        } else if (block.chainid == BASE_SEPOLIA_CHAINID) {
            chainlinkEthUsd = 0x0000000000000000000000000000000000000000;
            chainlinkBtcUsd = 0x0000000000000000000000000000000000000000;
            revert("No chainlink test oracles for Base yet");
        } else revert("Uninitialized oracle addresses for this chainid");
    }

    function run() external {
        init();

        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(); /*deployerPrivateKey*/

        console.log("Creator (owner): ", msg.sender);

        // SCH token
        IERC20Metadata SCH = IERC20Metadata(address(new MockERC20("SCH", "SCH", 18, 10**6 * 10**18))); // 1M total supply
        console.log("SCH token address: ", address(SCH));

        IScholesOption options = new ScholesOption();
        console.log(
            "ScholesOption deployed: ",
            address(options)
        );

        IScholesCollateral collaterals = new ScholesCollateral(address(options));
        console.log(
            "ScholesCollateral deployed: ",
            address(collaterals)
        );

        IScholesLiquidator liquidator = new ScholesLiquidator(address(options));
        console.log(
            "ScholesLiquidator deployed: ",
            address(liquidator)
        );

        ISpotPriceOracleApprovedList oracleList = new SpotPriceOracleApprovedList();
        console.log(
            "SpotPriceOracleApprovedList deployed: ",
            address(oracleList)
        );

        IOrderBookList obList = new OrderBookList(options);
        console.log(
            "OrderBookList deployed: ",
            address(obList)
        );

        ITimeOracle mockTimeOracle = new MockTimeOracle();
        console.log(
            "MockTimeOracle deployed: ",
            address(mockTimeOracle)
        );
        
        options.setFriendContracts(address(collaterals), address(liquidator), address(oracleList), address(obList), address(mockTimeOracle), address(SCH));
        collaterals.setFriendContracts();
        liquidator.setFriendContracts();
        // In order for the liquidation backstop to work, the liquidator must be funded with SCH, by staking using liquidator.stSCH().stake()

        // Now let's create some test Tokens, Oracles and Options

        // Test tokens:

        // Test USDC token
        IERC20Metadata USDC = IERC20Metadata(address(new MockERC20("Test USDC", "USDC", 6, 10**6 * 10**6))); // 1M total supply
        console.log("Test USDC address: ", address(USDC));
        USDC.transfer(account1, 100000 * 10**USDC.decimals());
        USDC.transfer(account2, 100000 * 10**USDC.decimals());
        USDC.transfer(account3, 100000 * 10**USDC.decimals());

        // Test WETH token
        IERC20Metadata WETH = IERC20Metadata(address(new MockERC20("Test WETH", "WETH", 18, 10**3 * 10**18))); // 1M total supply
        console.log("Test WETH address: ", address(WETH));
        WETH.transfer(account1, 100 * 10**WETH.decimals());
        WETH.transfer(account2, 100 * 10**WETH.decimals());
        WETH.transfer(account3, 100 * 10**WETH.decimals());

        // Test WBTC token
        IERC20Metadata WBTC = IERC20Metadata(address(new MockERC20("Test WBTC", "WBTC", 18, 10**3 * 10**18))); // 1M total supply
        console.log("Test WBTC address: ", address(WBTC));
        WBTC.transfer(account1, 100 * 10**WBTC.decimals());
        WBTC.transfer(account2, 100 * 10**WBTC.decimals());
        WBTC.transfer(account3, 100 * 10**WBTC.decimals());

        // Mock SCH/USDC oracle
        { // To avoid "stack too deep" error
        ISpotPriceOracle oracleSchUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd/*Irrelevant-always mock*/), SCH, USDC, false);
        oracleSchUsd.setMockPrice(1 * 10 ** oracleSchUsd.decimals()); // 1 SCH = 1 USDC
        console.log(
            "SCH/USDC SpotPriceOracle based on ETH/USD deployed, but always mocked: ",
            address(oracleSchUsd)
        );
        oracleList.addOracle(oracleSchUsd);
        }
        
        // Test Oracles:

        ISpotPriceOracle oracleEthUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkEthUsd), WETH, USDC, false);
        console.log(
            "WETH/USDC SpotPriceOracle based on ETH/USD deployed: ",
            address(oracleEthUsd)
        );
        oracleList.addOracle(oracleEthUsd);
    
        ISpotPriceOracle oracleBtcUsd = new SpotPriceOracle(AggregatorV3Interface(chainlinkBtcUsd), WBTC, USDC, false);
        console.log(
            "WBTC/USDC SpotPriceOracle based on BTC/USD deployed: ",
            address(oracleBtcUsd)
        );
        oracleList.addOracle(oracleBtcUsd);

        // Test Options:

        uint256 timeNow = options.timeOracle().getTime();
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_1;

        opt.isCall = true;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);

        IOrderBook ob = obList.getOrderBook(0); // The above WETH/USDC option
        console.log("WETH/USDC order book: ", address(ob));
        uint256 oid = ob.longOptionId();
        console.log("Long Option Id:", oid);
        options.setCollateralRequirements(options.getOpposite(oid)/*short*/, 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        require(keccak256("WETH") == keccak256(abi.encodePacked(options.getUnderlyingToken(oid).symbol())), "WETH symbol mismatch"); // Check
        require(opt.expiration == options.getExpiration(oid), "Expiration mismatch"); // Double-check

        if (keccak256(bytes(vm.envString("CREATE_TEST_ORDERS"))) == keccak256(bytes("yes"))) {
            console.log("Creating some test orders");

            vm.stopBroadcast();

            vm.startBroadcast(vm.envUint("PRIVATE_KEY_1"));
            USDC.approve(address(collaterals), type(uint256).max);
            WETH.approve(address(collaterals), type(uint256).max);
            collaterals.deposit(oid, 10000 * 10**USDC.decimals(), 10 ether);
            ob.make(-1 ether, 3 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(-2 ether, 1 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(-1 ether, 2 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(-1 ether, 1 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            vm.stopBroadcast();

            vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));
            USDC.approve(address(collaterals), type(uint256).max);
            WETH.approve(address(collaterals), type(uint256).max);
            collaterals.deposit(oid, 10000 * 10**USDC.decimals(), 10 ether);
            ob.make(3 ether, 2 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(2 ether, 3 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(1 ether, 1 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            ob.make(2 ether, 2 ether, mockTimeOracle.getTime() + 7 * 24 * 60 * 60 /* 7 days */);
            vm.stopBroadcast();
            
            vm.startBroadcast(); /*deployerPrivateKey*/
        }
        }

        // Some more test options
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_2;
        opt.isCall = true;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_3;
        opt.isCall = true;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_4;
        opt.isCall = true;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_1;
        opt.isCall = false;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_2;
        opt.isCall = false;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_3;
        opt.isCall = false;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WETH;
        opt.base = USDC;
        opt.strike = 2000 * 10 ** oracleEthUsd.decimals();
        opt.expiration = EXPIRATION_4;
        opt.isCall = false;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
        {
        TOptionParams memory opt;
        opt.underlying = WBTC;
        opt.base = USDC;
        opt.strike = 35000 * 10 ** oracleBtcUsd.decimals();
        opt.expiration = EXPIRATION_1;
        opt.isCall = true;
        opt.isAmerican = false;
        opt.isLong = true;
        obList.createScholesOptionPair(opt);
        options.setCollateralRequirements(options.getOpposite(obList.getOrderBook(obList.getLength()-1).longOptionId()), 0, 0, timeNow, ""); // No collateral requirements (this is dangerous!!!)
        console.log("Long Option Id:", obList.getOrderBook(obList.getLength()-1).longOptionId());
        }
        
    }
}
