// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/token/ERC1155/IERC1155.sol";

import "../types/TOptionParams.sol";
import "../types/TCollateralRequirements.sol";

import "./IScholesCollateral.sol";
import "./IScholesLiquidator.sol";
import "./ISpotPriceOracle.sol";
import "./ISpotPriceOracleApprovedList.sol";
import "./IOrderBookList.sol";
import "./ITimeOracle.sol";

interface IScholesOption is IERC1155 {
    event SettlementPrice(uint256 indexed id, uint256 settlementPrice);
    event Exercise(uint256 indexed id, address indexed holder, uint256 amount, uint256 timestamp, bool toUnderlying);
    event Settle(uint256 indexed id, address indexed holder, uint256 amount, uint256 timestamp, bool spotNotSettlement);

    function setFriendContracts(address _collaterals, address _liquidator, address _spotPriceOracleApprovedList, address _orderBookList, address _timeOracle, address _schToken) external;
    function authorizeExchange(uint256 id, address ob) external;
    function isAuthorizedExchange(uint256 id, address exchange) external view returns (bool);
    function collaterals() external view returns (IScholesCollateral);
    function liquidator() external view returns (IScholesLiquidator);
    function spotPriceOracleApprovedList() external view returns (ISpotPriceOracleApprovedList);
    function orderBookList() external view returns (IOrderBookList);
    function spotPriceOracle(uint256 id) external view returns (ISpotPriceOracle);
    function schToken() external view returns (IERC20Metadata);
    function schTokenSpotOracle(uint256 id) external view returns (ISpotPriceOracle);
    function timeOracle() external view returns (ITimeOracle);
    function numHolders(uint256 id) external view returns (uint256);
    function getHolder(uint256 id, uint256 index) external view returns (address);
    function isCall(uint256 id) external view returns (bool);
    function isLong(uint256 id) external view returns (bool);
    function isAmerican(uint256 id) external view returns (bool);
    function getStrike(uint256 id) external view returns (uint256);
    function getExpiration(uint256 id) external view returns (uint256);
    function getOpposite(uint256 id) external view returns (uint256);
    function getLongOptionId(uint256 id) external view returns (uint256);
    function getBaseToken(uint256 id) external view returns (IERC20Metadata);
    function getUnderlyingToken(uint256 id) external view returns (IERC20Metadata);
    function setCollateralRequirements(uint256 id, uint256 entryCollateralRequirement, uint256 maintenanceCollateralRequirement, uint256 timestamp, bytes calldata proof) external;
    function getCollateralRequirementThreshold(uint256 id, bool entry) external view returns (uint256);
    function collateralRequirement(address holder, uint256 id, bool entry) external view returns (uint256 requirement, uint256 possession);
    function collateralRequirement(uint256 amount, uint256 id, bool entry) external view returns (uint256);
    function isCollateralSufficient(address holder, uint256 id, bool entry) external view returns (bool);
    function createOptionPair(TOptionParams memory optionParams) external returns (uint256 longId, uint256 shortId);
    function calculateOptionId(IERC20Metadata underlying, IERC20Metadata base, uint256 strike, uint256 expiration, bool isCall, bool isAmerican, bool isLong) external pure returns (uint256);
    function exercise(uint256 id, uint256 amount, bool toUnderlying, address[] memory holders, uint256[] memory amounts) external;
    function setSettlementPrice(uint256 id) external;
    function getSettlementPrice(uint256 id) external view returns (uint256);
    function settle(uint256 id) external;
    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;
    function burn(address from, uint256 id, uint256 amount) external;
    function proxySafeTransferFrom(address from, address to, uint256 id, uint256 amount) external;
}