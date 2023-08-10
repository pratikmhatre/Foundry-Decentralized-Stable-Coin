// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DscEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    DSCEngine engine;
    DecentralizedStableCoin dsc;
    address private wethAddress;
    address private wethPriceFeedAddress;
    address private btcAddress;
    address private btcPriceFeedAddress;

    uint256 private constant COLLATERAL_AMOUNT = 10 ether;
    uint256 private constant COLLATERAL_IN_USD = 20000e18;
    address private USER = makeAddr("user");
    uint256 private USER_BALANCE = 15 ether;

    function setUp() external {
        HelperConfig helperConfig;
        DeployDSC deploy = new DeployDSC();
        (dsc, engine, helperConfig) = deploy.run();
        (wethAddress, wethPriceFeedAddress, btcAddress, btcPriceFeedAddress,) = helperConfig.activNetworkConfig();
        vm.deal(USER, USER_BALANCE);
        ERC20Mock(wethAddress).mint(USER, USER_BALANCE);
    }

    function testGetTokenValueInUSD() external view {
        uint256 expectedValue = 2000e18;
        uint256 actualValue = engine.getTokenValueInUsd(wethAddress, 1e18);
        assert(expectedValue == actualValue);
    }

    ////////////////////////////
    ///Constructor Tests/////////
    /////////////////////////

    address[] tokens;
    address[] priceFeeds;

    function testInvalidCollateralToPriceFeedDataReverts() external {
        tokens.push(wethAddress);
        priceFeeds.push(wethPriceFeedAddress);
        priceFeeds.push(address(0));

        vm.expectRevert(DSCEngine.DSC__InvalidCollateralToPricefeedData.selector);
        new DSCEngine(tokens, priceFeeds, address(dsc));
    }

    //Deposit Collateral
    function testZeroCollateralRevertsError() external {
        vm.expectRevert(DSCEngine.DSCEngine__RequiresAmountGreaterThanZero.selector);
        engine.depositCollateral(wethAddress, 0);
    }

    function testDepositCollateralIncreasedUserCollateralBalance() external depositCollateral {
        vm.prank(USER);
        assert(engine.getUserCollateralByTokenAddress(wethAddress) == COLLATERAL_AMOUNT);
    }

    //mint DSC
    function testMintDscRevertsIfDscAmountIsZero() external depositCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__RequiresAmountGreaterThanZero.selector);
        engine.mintDSC(0);
    }

    function testMintDSCRevertsIfHealthFactorBreaks() external depositCollateral {
        vm.expectRevert();
        vm.prank(USER);
        engine.mintDSC(1000000000000000000000000000000000000000000000000000000000);
    }

    function testMintDSCIncreasesUsersDSCBalance() external depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(10000e18);
        (uint256 dscMinted,) = engine.getUserAccountInfo(USER);
        vm.stopPrank();
        assert(dscMinted == 10000e18);
    }

    //deposit & mint
    function testDepositeCollateralAndMintChangesUserBalance() external {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDSC(wethAddress, COLLATERAL_AMOUNT, 10000e18);
        uint256 dscBalance = engine.getDscOfUser(USER);
        uint256 collateralInUSD = engine.getUserCollateralValueInUsd(USER);
        vm.stopPrank();
        assert(dscBalance == 10000e18);
        assert(collateralInUSD == COLLATERAL_IN_USD); //10 ether
    }

    //get account info
    function testGetAccountInfo() external depositCollateral {
        uint256 expectedDSCAmount = 5000e18;
        vm.startPrank(USER);
        engine.mintDSC(expectedDSCAmount);
        (uint256 dscMinted, uint256 collateralInUsd) = engine.getUserAccountInfo(USER);
        vm.stopPrank();

        assert(dscMinted == expectedDSCAmount);
        assert(collateralInUsd == COLLATERAL_IN_USD);
    }

    //token to usd
    function testTokenValueInUsd() external view {
        uint256 value = engine.getTokenValueInUsd(wethAddress, 5e18);
        uint256 expectedValue = 2000e18 * 5;
        assert(value == expectedValue);
    }

    //redeem collateral
    function testRedeemCollateralFailsIfNoCollateralPresent() external {}
    function testRedeemCollateralIfHealthFactorBreaks() external {}
    function testRedeemCollateralEmitsCollateralRedeemedEvent() external {}

    //burn dsc
    function testBurnDSCReducesUserDSCBalance() external {}

    //liquidate user
    function testLiquidateUserRevertsIfHealthFactorOk() external {}
    function testLiquidateUserReducesUsersDSCBalance() external {}
    function testLiquidateUserReducesUsersCollateral() external {}
    function testLiquidateUserEmitsTransferSuccess() external {}
    function testLiquidateUserMakesHealthFactorOk() external {}

    ////////////////////////////
    ///Modifiers/////////
    /////////////////////////

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wethAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralBtc() {
        vm.startPrank(USER);
        ERC20Mock(btcAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(btcPriceFeedAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }
}
