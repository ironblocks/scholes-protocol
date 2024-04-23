// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import "openzeppelin-contracts/security/Pausable.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "openzeppelin-contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "./interfaces/IScholesOption.sol";
import "./interfaces/IScholesCollateral.sol";
import "./interfaces/IScholesLiquidator.sol";

contract ScholesCollateral is IScholesCollateral, ERC1155, Pausable, Ownable, ERC1155Supply {
    IScholesOption options;
    IScholesLiquidator liquidator;

    struct TCollateralPurpose {
        uint256 optionId;
        bool isBase;
    }
    mapping (uint256 => TCollateralPurpose) purpose; // id => TCollateralPurpose; to find out the purpose of an id

    constructor(address _options) ERC1155("https://scholes.xyz/collateral.json") {
        options = IScholesOption(_options);
    }

    function setFriendContracts() external {
        liquidator = IScholesLiquidator(options.liquidator());
    }

    modifier onlyExchangeOrOptions(uint256 id) {
        require(msg.sender == address(options) || options.isAuthorizedExchange(id, msg.sender), "Unauthorized");
        _;
    }

    modifier onlyOptionsOrLiquidator() {
        require(msg.sender == address(options) || msg.sender == address(liquidator), "Unauthorized");
        _;
    }

    function getId(uint256 optionId, bool isBase) public view returns (uint256) {
        optionId = options.getLongOptionId(optionId); // Same collateral for both long and short options
        return uint256(keccak256(abi.encodePacked(optionId, isBase)));
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function totalSupply(uint256 id) public view override(ERC1155Supply, IScholesCollateral) returns (uint256) {
        return super.totalSupply(id);
    }

    function mintCollateral(address to, uint256 id, uint256 amount) external onlyOptionsOrLiquidator {
        _mint(to, id, amount, "");
    }

    function burnCollateral(address from, uint256 id, uint256 amount) external onlyOptionsOrLiquidator {
        _burn(from, id, amount);
    }

    // To cover "transfer" calls which return bool and/or revert
    function safeERC20Transfer(IERC20 token, address to, uint256 amount) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    // Some tokens revert and some return false on failure. This covers both.
    function safeTransferERC20From(address token, address from, address to, uint256 amount) private {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function deposit(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount) external {
        safeTransferERC20From(address(options.getBaseToken(optionId)), msg.sender, address(this), baseAmount); // Can revert
        safeTransferERC20From(address(options.getUnderlyingToken(optionId)), msg.sender, address(this), underlyingAmount); // Can revert
        uint256[] memory ids = new uint256[](2);
        ids[0] = getId(optionId, true);
        if (0 == purpose[ids[0]].optionId) // Record for inverse mapping
            purpose[ids[0]] = TCollateralPurpose(optionId, true);
        ids[1] = getId(optionId, false);
        if (0 == purpose[ids[1]].optionId) // Record for inverse mapping
            purpose[ids[1]] = TCollateralPurpose(optionId, false);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = baseAmount;
        amounts[1] = underlyingAmount;
        _mintBatch(msg.sender, ids, amounts, "");
        emit Deposit(msg.sender, optionId, baseAmount, underlyingAmount);
    }

    function withdraw(uint256 optionId, uint256 baseAmount, uint256 underlyingAmount) external {
        (uint256 baseBalance, uint256 underlyingBalance) = balances(msg.sender, optionId);
        require(baseBalance >= baseAmount, "Insufficient base balance");
        require(underlyingBalance >= underlyingAmount, "Insufficient underlying balance");
        uint256[] memory ids = new uint256[](2);
        ids[0] = getId(optionId, true);
        ids[1] = getId(optionId, false);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = baseAmount;
        amounts[1] = underlyingAmount;
        // Optimistically withdraw
        safeERC20Transfer(options.getBaseToken(optionId), msg.sender, baseAmount);
        safeERC20Transfer(options.getUnderlyingToken(optionId), msg.sender, underlyingAmount);
        // Now burn and enforce collateralization (in _burnBatch->_afterTokenTransfer)
        _burnBatch(msg.sender, ids, amounts);
        require(options.isCollateralSufficient(msg.sender, optionId, /*entry*/true), "Undercollateralized"); // See analysis in _afterTokenTransfer
        emit Withdraw(msg.sender, optionId, baseAmount, underlyingAmount);
    }

    function balances(address owner, uint256 optionId) public view returns (uint256 baseBalance, uint256 underlyingBalance) {
        if (address(0) == owner) return (0, 0);
        uint256[] memory ids = new uint256[](2);
        ids[0] = getId(optionId, true);
        ids[1] = getId(optionId, false);
        address[] memory owners = new address[](2);
        owners[0] = owners[1] = owner;
        uint256[] memory bal = balanceOfBatch(owners, ids);
        baseBalance = bal[0];
        underlyingBalance = bal[1];
    }

    function proxySafeTransferFrom(uint256 optionId, address from, address to, uint256 id, uint256 amount) external onlyExchangeOrOptions(optionId) {
        _safeTransferFrom(from, to, id, amount, "");
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _afterTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155)
    {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
        // Transfer was optimistically completed
        // Now enforce entry collateral requirements
        for (uint256 i = 0; i<ids.length; i++) {
            bool entry = true; // true is worst case. Not optimal but safe.

            // If this is deposit, the holder is a recipient of funds: do not enforce collateralization as it is improving
            if (from == address(0)) continue; // Minting - happens upon deposit - skip enforcement

            // If this is a withdrawal, enforce ENTRY collateralization
            else if (to == address(0)) entry = true;

            // If this is a premium payment, the holder is increasing long position or decreasing short position: enforce MAINTENANCE collateral
            //   Additional concern: what if the premium payment is larger than the improvement of collateralization? (this should not happen)
            //      This depends on ScholesOption.isCollateralSufficient, which has to be carefully designed so the above concern is not true.
            //      In practice this can happen if the short option quickly becomes huge liability upon sudden market moves.
            // If this is a premium receipt for short position: the enforcement will happen upon transfer of the option; for now there is no 
            //      need to enforce collateralization (this case implementation is not optimal - we should not check at all).
            else entry = false;

            require(options.isCollateralSufficient(from, purpose[ids[i]].optionId, entry), "Undercollateralized collateral sender"); // This checks both the Base and Underlying parts of the collateral
        }
    }
}