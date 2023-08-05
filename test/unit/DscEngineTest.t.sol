// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";

contract DscEngineTest is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    address private wethAddress;
    address private wethPriceFeedAddress;

    uint256 private constant COLLATERAL_AMOUNT = 10 ether;
    address private USER = makeAddr("user");

    function setUp() external {
        HelperConfig helperConfig;
        DeployDSC deploy = new DeployDSC();
        (dsc, engine, helperConfig) = deploy.run();
        (wethAddress, wethPriceFeedAddress, , , ) = helperConfig
            .activNetworkConfig();
    }

    function testGetTokenValueInUSD() external view {
        uint256 expectedValue = 2000e18;
        uint256 actualValue = engine.getTokenValueInUsd(wethAddress, 1e18);
        assert(expectedValue == actualValue);
    }

    function testZeroCollateralRevertsError() external {
        vm.expectRevert(
            DSCEngine.DSCEngine__RequiresAmountGreaterThanZero.selector
        );
        engine.depositCollateral(wethAddress, 0);
    }
}
