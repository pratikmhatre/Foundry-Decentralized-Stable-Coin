// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address wethAddress;
    address wbtcAddress;
    address wethPriceFeed;
    address wbtcPriceFeed;
    Handler handler;

    function setUp() external {
        DeployDSC deploy = new DeployDSC();
        (dsc, engine, helperConfig) = deploy.run();
        (wethAddress, wethPriceFeed, wbtcAddress, wbtcPriceFeed,) = helperConfig.activNetworkConfig();
        handler = new Handler(dsc,engine,wethAddress,wbtcAddress, wethPriceFeed, wbtcPriceFeed);
        targetContract(address(handler));
    }

    function invariant_TotalDSCShouldAlwaysBeLessThanTotalCollateral() external view {
        uint256 totalDSC = dsc.totalSupply();

        uint256 wbtcBalance = IERC20(wbtcAddress).balanceOf(address(engine));
        uint256 totalBtcValue = engine.getTokenValueInUsd(wbtcAddress, wbtcBalance);

        uint256 wethBalance = IERC20(wethAddress).balanceOf(address(engine));
        uint256 totalEthValue = engine.getTokenValueInUsd(wethAddress, wethBalance);
        uint256 totalCollateralInUsd = totalBtcValue + totalEthValue;
        console.log("BTC Balance", wbtcBalance);
        console.log("ETH Balance", wethBalance);
        console.log("Total DSC", totalDSC);
        console.log("Min Called", handler.mintCalled());
        assert(totalDSC <= totalCollateralInUsd);
    }

    /* function invariant_GetterFunctionsShouldNeverRevert(
        uint256 addressSeed,
        address userAddress,
        uint256 tokenAmount,
        uint256 usdAmount
    ) external view {
        tokenAmount = bound(tokenAmount, 1 ether, type(uint96).max);
        address collateralAddress = _getValidCollateralAddress(addressSeed);

        engine.getDscOfUser(userAddress);

        engine.getTokenAmountFromUSD(collateralAddress, usdAmount);
        engine.getTokenValueInUsd(collateralAddress, tokenAmount);
        engine.getUserAccountInfo(userAddress);
        engine.getUserCollateralByTokenAddress(collateralAddress);
        engine.getUserCollateralValueInUsd(userAddress);
    } */
}
