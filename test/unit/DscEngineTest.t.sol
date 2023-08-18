// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DscEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event TransferSuccess(uint256 transferAmount);
    event SomethingHappened(uint256 transferAmount);
    event CollateralRedeemed(
        address indexed tokenAddress, address indexed sender, address indexed receiver, uint256 amount
    );

    DSCEngine engine;
    DecentralizedStableCoin dsc;
    address private wethAddress;
    address private wethPriceFeedAddress;
    address private btcAddress;
    address private btcPriceFeedAddress;

    uint256 private constant COLLATERAL_AMOUNT = 10 ether;
    uint256 private constant COLLATERAL_IN_USD = 20000 * 10 ** 18; //2000e18 per ether
    uint256 private constant DSC_TO_MINT = 10000 ether; //Last safe DSC amount
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

    //Token to USD
    function testGetTokenValueInUsd() external view {
        uint256 expectedValue = 4000e18; //4000 USD
        uint256 actualValue = engine.getTokenValueInUsd(wethAddress, 2 ether);
        assert(expectedValue == actualValue);
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
        engine.mintDSC(DSC_TO_MINT + 1);
    }

    function testMintDSCIncreasesUsersDSCBalance() external depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(DSC_TO_MINT);
        (uint256 dscMinted,) = engine.getUserAccountInfo(USER);
        vm.stopPrank();
        assert(dscMinted == DSC_TO_MINT);
    }

    //deposit & mint

    function testDepositCollateralAndMintDscRevertsIfDscAmountBreaksHealthFactor() external {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__PoorHealthFactor.selector, 0));
        engine.depositCollateralAndMintDSC(wethAddress, COLLATERAL_AMOUNT, DSC_TO_MINT + 1);
        vm.stopPrank();
    }

    function testDepositeCollateralAndMintChangesUserBalance() external {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDSC(wethAddress, COLLATERAL_AMOUNT, DSC_TO_MINT);
        uint256 dscBalance = engine.getDscOfUser(USER);
        uint256 collateralInUSD = engine.getUserCollateralValueInUsd(USER);
        vm.stopPrank();
        assert(dscBalance == DSC_TO_MINT);
        assert(collateralInUSD == COLLATERAL_IN_USD);
    }

    //get account info
    function testGetAccountInfo() external depositCollateralAndMintDSC {
        vm.startPrank(USER);
        (uint256 dscMinted, uint256 collateralInUsd) = engine.getUserAccountInfo(USER);
        vm.stopPrank();

        assert(dscMinted == DSC_TO_MINT);
        assert(collateralInUsd == COLLATERAL_IN_USD);
    }

    //token to usd
    function testTokenValueInUsd() external view {
        uint256 value = engine.getTokenValueInUsd(wethAddress, 5e18);
        uint256 expectedValue = 2000e18 * 5;
        assert(value == expectedValue);
    }

    //redeem collateral
    function testRedeemCollateralFailsIfNoCollateralPresent() external {
        vm.expectRevert();
        vm.prank(USER);
        engine.redeemCollateral(wethAddress, 100);
    }

    function testRedeemCollateralRevertsIfHealthFactorBreaks() external depositCollateral {
        vm.startPrank(USER);
        engine.mintDSC(DSC_TO_MINT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__PoorHealthFactor.selector, 0));
        engine.redeemCollateral(wethAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsCollateralRedeemedEvent() external depositCollateral {
        vm.startPrank(USER);
        vm.expectEmit();
        emit CollateralRedeemed(wethAddress, USER, USER, COLLATERAL_AMOUNT);
        engine.redeemCollateral(wethAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsTransferSuccessEvent() external depositCollateral {
        vm.startPrank(USER);
        vm.expectEmit();
        emit TransferSuccess(COLLATERAL_AMOUNT);
        engine.redeemCollateral(wethAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    //burn dsc

    function testBurnDSCReducesUserDSCBalance() external depositCollateralAndMintDSC {
        vm.startPrank(USER);
        dsc.approve(address(engine), DSC_TO_MINT);
        engine.burnDSC((DSC_TO_MINT / 2));
        uint256 dscBalance = engine.getDscOfUser(USER);
        assert(dscBalance == (DSC_TO_MINT / 2));
        vm.stopPrank();
    }

    //Get token amount from USD value
    function testGetTokenFromUSDGivesCorrectAnswer() external {
        int256 newEthValue = 1200e8;
        _depriciateEthValue(newEthValue);

        uint256 expectedValue = 4 ether;
        uint256 actualValue = engine.getTokenAmountFromUSD(wethAddress, 4800 ether);
        assert(actualValue == expectedValue);
    }

    //400000000

    //liquidate user
    function testLiquidateUserRevertsIfHealthFactorOk() external depositCollateralAndMintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidateUser(USER, wethAddress, 1 ether);
        vm.stopPrank();
    }

    function testLiquidateUserClearsUsersDSCDebt() external {
        (address user1,,) = _createUserWithBalance(111, 100000 ether, 50000 ether);
        (address user2,,) = _createUserWithBalance(222, 50 ether, 50000 ether);

        _depriciateEthValue(1500e8);

        vm.startPrank(user1);
        dsc.approve(address(engine), 50000 ether);
        engine.liquidateUser(user2, wethAddress, 50000 ether);
        vm.stopPrank();

        assert(engine.getDscOfUser(user2) == 0);
    }

    function testLiquidateUserReducesUsersCollateral() external {
        (address user1,,) = _createUserWithBalance(111, 100000 ether, 50000 ether);
        (address user2,,) = _createUserWithBalance(222, 50 ether, 50000 ether);

        _depriciateEthValue(1500e8);

        vm.startPrank(user1);
        dsc.approve(address(engine), 50000 ether);
        engine.liquidateUser(user2, wethAddress, 50000 ether);
        vm.stopPrank();

        uint256 debtInEth = engine.getTokenAmountFromUSD(wethAddress, 50000 ether);
        uint256 bonus = (debtInEth * 10) / 100;
        uint256 expectCollateralTransferred = 50 ether - (debtInEth + bonus);

        vm.prank(user2);
        assert(engine.getUserCollateralByTokenAddress(wethAddress) == expectCollateralTransferred);
    }

    function testLiquidateUserEmitsTransferSuccess() external {
        (address user1,,) = _createUserWithBalance(111, 100000 ether, 50000 ether);
        (address user2,,) = _createUserWithBalance(222, 50 ether, 50000 ether);

        _depriciateEthValue(1500e8);

        vm.startPrank(user1);
        dsc.approve(address(engine), 50000 ether);

        uint256 debtInEth = engine.getTokenAmountFromUSD(wethAddress, 50000 ether);
        uint256 bonus = (debtInEth * 10) / 100;
        uint256 expectCollateralTransferred = debtInEth + bonus;

        vm.expectEmit();
        emit TransferSuccess(expectCollateralTransferred);

        engine.liquidateUser(user2, wethAddress, 50000 ether);
        vm.stopPrank();
    }

    function testLiquidateUserMakesHealthFactorOk() external {
        (address user1,,) = _createUserWithBalance(111, 100000 ether, 50000 ether);
        (address user2,,) = _createUserWithBalance(222, 50 ether, 50000 ether);

        _depriciateEthValue(1500e8);

        vm.startPrank(user1);
        dsc.approve(address(engine), 50000 ether);
        engine.liquidateUser(user2, wethAddress, 50000 ether);
        vm.stopPrank();

        assert(engine.calculateHealthFactor(user2) >= 1);
    }

    /* 
    1. Create user 1 deposit 20 and mint 10
    2. Create user 2 deposit 10 and mint 5
    3. Depriciate eth value and check user two health factor
    4. if health factor is low , make user 1 to liquidate user 2's entire collateral
    */

    function _createUserWithBalance(uint160 userId, uint256 collateralToDeposit, uint256 dscToMint)
        internal
        returns (address, uint256, uint256)
    {
        address user1 = address(userId);
        ERC20Mock(wethAddress).mint(user1, collateralToDeposit);
        vm.startPrank(user1);
        ERC20Mock(wethAddress).approve(address(engine), collateralToDeposit);
        engine.depositCollateralAndMintDSC(wethAddress, collateralToDeposit, dscToMint);
        vm.stopPrank();
        return (user1, collateralToDeposit, dscToMint);
    }

    function _getLatestEthPrice() internal view returns (int256) {
        MockV3Aggregator agg = MockV3Aggregator(wethPriceFeedAddress);
        // agg.updateAnswer(1000 ether);
        (, int256 price,,,) = agg.latestRoundData();
        return price;
    }

    function _depriciateEthValue(int256 newValue) internal {
        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(newValue);
    }

    ////////////////////////////
    ///Modifiers/////////
    /////////////////////////

    modifier depreciateCollateral() {
        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(0);
        _;
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wethAddress, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintDSC(wethAddress, COLLATERAL_AMOUNT, DSC_TO_MINT);
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
