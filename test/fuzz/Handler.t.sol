// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    address wethAddress;
    address wbtcAddress;
    uint256 MAX_COLLATERAL = type(uint96).max;
    uint256 public mintCalled = 0;
    address[] usersWithCollateral;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _engine, address _wethAddress, address _wbtcAddress) {
        dsc = _dsc;
        engine = _engine;
        wethAddress = _wethAddress;
        wbtcAddress = _wbtcAddress;
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) external {
        address collateralAddress = _getValidCollateralAddress(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_COLLATERAL);
        _getFundedUser(collateralAddress, collateralAmount);
        usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) external {
        address collateralAddress = _getValidCollateralAddress(collateralSeed);
        uint256 collateralDeposited = engine.getUserCollateralByTokenAddress(collateralAddress);
        amount = bound(amount, 0, collateralDeposited);
        if (amount == 0) return;
        engine.redeemCollateral(collateralAddress, amount);
    }

    function mintDsc(uint256 amount, uint256 userAddressSeed) external {
        if (usersWithCollateral.length == 0) return;
        address userAddress = usersWithCollateral[userAddressSeed % usersWithCollateral.length];

        mintCalled++;
        vm.startPrank(userAddress);
        (uint256 dscMinted, uint256 collateralInUsd) = engine.getUserAccountInfo(userAddress);
        int256 maxDSCAmountToMint = (int256(collateralInUsd) / 2) - int256(dscMinted);

        if (maxDSCAmountToMint <= 0) return;

        amount = bound(amount, 1, uint256(maxDSCAmountToMint));
        engine.mintDSC(amount);
        vm.stopPrank();
    }

    function _getValidCollateralAddress(uint256 seed) internal view returns (address) {
        if (seed % 2 == 0) {
            return wethAddress;
        } else {
            return wbtcAddress;
        }
    }

    function _getFundedUser(address collateral, uint256 collateralAmount) internal returns (address) {
        // address user = address(uint160(block.timestamp));
        vm.startPrank(msg.sender);
        ERC20Mock(collateral).mint(msg.sender, collateralAmount);
        ERC20Mock(collateral).approve(address(engine), collateralAmount);
        engine.depositCollateral(collateral, collateralAmount);
        vm.stopPrank();
        return msg.sender;
    }
}
