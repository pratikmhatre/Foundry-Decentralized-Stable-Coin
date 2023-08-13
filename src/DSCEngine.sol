// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngine is ReentrancyGuard {
    //////////////
    ///Errors/////
    //////////////
    error DSCEngine__RequiresAmountGreaterThanZero();
    error DSCEngine__TokenNotSupported();
    error DSC__MintingFailed();
    error DSCEngine__PoorHealthFactor(uint256);
    error DSCEngine__HealthFactorOk();
    error DSC__TransferFailed();
    error DSC__HealthFactorNotImproved();
    error DSC__InvalidCollateralToPricefeedData();

    //////////////
    ///Events/////
    //////////////
    event SomethingHappened(uint256 a, address b, address c);
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event TransferSuccess(uint256 transferAmount);
    event CollateralRedeemed(
        address indexed tokenAddress,
        address indexed sender,
        address indexed receiver,
        uint256 amount
    );
    event DSCBurned(address indexed user, uint256 dscAmount);

    //////////////////////
    ///State Variables/////
    //////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 balance)) s_userCollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_tokens;

    //////////////////////
    ///Constants/////
    //////////////////////
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% Bonus to liquidator

    //////////////////////
    ///Immutables/////////
    //////////////////////
    DecentralizedStableCoin private immutable i_dsc;

    constructor(
        address[] memory tokens,
        address[] memory priceFeeds,
        address dscAddress
    ) {
        if (tokens.length != priceFeeds.length)
            revert DSC__InvalidCollateralToPricefeedData();

        i_dsc = DecentralizedStableCoin(dscAddress);
        for (uint256 i = 0; i < tokens.length; i++) {
            s_priceFeeds[tokens[i]] = priceFeeds[i];
            s_tokens.push(tokens[i]);
        }
    }

    //////////////////////
    ///Public Functions/////
    //////////////////////
    function depositCollateralAndMintDSC(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 dscAmount
    ) external {
        depositCollateral(tokenAddress, tokenAmount);
        mintDSC(dscAmount);
    }

    /**
     * mintDSC - The function takes the DSC amount to be minted and mints equivalent DSC tokens after
     * ensuring the health factor doesnt break after transaction
     * @param amount - Amount of DSC to be minted
     */
    function mintDSC(
        uint256 amount
    ) public checkAmountGreaterThanZero(amount) nonReentrant {
        s_dscMinted[msg.sender] += amount;

        bool result = i_dsc.mint(msg.sender, amount);
        if (!result) revert DSC__MintingFailed();

        _revertIfHealthFactorBroken(msg.sender);
    }

    /**
     * depositCollateral this function takes tokenAddress and token amount and transfers the token
     * amount from sender to this contract as collateral
     * @param tokenAddress : Address of token which considered valid collateral
     * @param tokenAmount : Amount of the token to be transferred as collateral to this contract
     */
    function depositCollateral(
        address tokenAddress,
        uint256 tokenAmount
    )
        public
        onlyAllowedToken(tokenAddress)
        checkAmountGreaterThanZero(tokenAmount)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][tokenAddress] = tokenAmount;
        emit CollateralDeposited({
            user: msg.sender,
            token: tokenAddress,
            amount: tokenAmount
        });
        bool transferSuccess = IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );
        if (!transferSuccess) revert DSC__TransferFailed();
    }

    function getUserAccountInfo(
        address userAddress
    ) public view returns (uint256 dscMinted, uint256 collateralValueInUsd) {
        dscMinted = s_dscMinted[userAddress];
        collateralValueInUsd = getUserCollateralValueInUsd(userAddress);
    }

    function getTokenValueInUsd(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface v3Interface = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = v3Interface.latestRoundData();
        //feed precision -> 1e10
        //precision -> 1e18;
        return (uint256(price) * FEED_PRECISION * amount) / PRECISION;
    }

    function redeemCollateralForDSC(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 dscAmount
    ) external onlyAllowedToken(tokenAddress) nonReentrant {
        burnDSC(dscAmount);
        redeemCollateral(tokenAddress, tokenAmount);
    }

    /**
     * @dev This function is called my user to redeem his own collateral
     * @param tokenAddress - Address of token collateral to be redeemes
     * @param tokenAmount  - Amount of collateral to be removed
     */
    function redeemCollateral(
        address tokenAddress,
        uint256 tokenAmount
    ) public checkAmountGreaterThanZero(tokenAmount) {
        _redeemCollateral(tokenAddress, tokenAmount, msg.sender, msg.sender); //deduct from sender's deposit in contract and send it to user's own wallet
        _revertIfHealthFactorBroken(msg.sender);
    }

    function burnDSC(
        uint256 dscAmount
    ) public checkAmountGreaterThanZero(dscAmount) {
        _burnDSC(dscAmount, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    function liquidateUser(
        address user,
        address collateral,
        uint256 debtToCoverInDSC
    ) external checkAmountGreaterThanZero(debtToCoverInDSC) {
        uint256 initialHealthFactor = calculateHealthFactor(user);
        if (initialHealthFactor >= MIN_HEALTH_FACTOR)
            revert DSCEngine__HealthFactorOk();

        uint256 debtInTokens = getTokenAmountFromUSD(
            collateral,
            debtToCoverInDSC
        );
        uint256 bonusTokens = (debtInTokens * LIQUIDATION_BONUS) / 100;
        uint256 totalTokens = debtInTokens + bonusTokens; // This amount of tokens will be sent to liquidator

        //Transfer totalTokens(eth) from user's collateral to liquidator
        _redeemCollateral(collateral, totalTokens, user, msg.sender);

        //Reduce user's debt and burn equivalent amount of DSC from liquidator
        _burnDSC(debtToCoverInDSC, user, msg.sender);

        uint256 finalHealthFactor = calculateHealthFactor(user);

        if (finalHealthFactor <= initialHealthFactor)
            revert DSC__HealthFactorNotImproved();

        _revertIfHealthFactorBroken(msg.sender);
    }

    function getTokenAmountFromUSD(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = aggregator.latestRoundData();
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * FEED_PRECISION));
    }

    //////////////////////
    ///Internal Functions/////
    //////////////////////
    function _burnDSC(
        uint256 dscAmount,
        address onBehalfOf,
        address dscFrom
    ) internal {
        //remove dsc from user's account
        s_dscMinted[onBehalfOf] -= dscAmount;
        emit DSCBurned(msg.sender, dscAmount);

        //take DSC from liquidator to this contract
        bool isSuccess = i_dsc.transferFrom(dscFrom, address(this), dscAmount);
        if (!isSuccess) revert DSC__TransferFailed();
        i_dsc.burn(dscAmount);
    }

    function _redeemCollateral(
        address token,
        uint256 tokenAmount,
        address from,
        address to
    ) internal {
        s_userCollateralDeposited[from][token] -= tokenAmount;
        emit CollateralRedeemed(token, from, to, tokenAmount);

        bool isSuccess = IERC20(token).transfer(to, tokenAmount);
        if (!isSuccess) revert DSC__TransferFailed();
        emit TransferSuccess(tokenAmount);
    }

    function _revertIfHealthFactorBroken(address userAddress) internal view {
        uint256 hf = calculateHealthFactor(userAddress);
        if (hf < MIN_HEALTH_FACTOR) revert DSCEngine__PoorHealthFactor(hf);
    }

    function calculateHealthFactor(
        address userAddress
    ) public view returns (uint256) {
        (uint256 dscMinted, uint256 collateralValueInUsd) = getUserAccountInfo(
            userAddress
        );

        if (dscMinted == 0) return MIN_HEALTH_FACTOR + 1;

        //LIQUIDATION_THRESHOLD = 50
        //LIQUIDATION_PRECISION = 100
        //factor = 0.5 ie, minted dsc should not be more than (collateral in USD / 2)

        uint256 collateralAdjustedToThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return collateralAdjustedToThreshold / dscMinted;
    }

    //////////////
    ///Modifiers//
    //////////////
    modifier onlyAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    modifier checkAmountGreaterThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__RequiresAmountGreaterThanZero();
        _;
    }

    //////////////////////
    ///getter functions/////
    //////////////////////
    function getUserCollateralByTokenAddress(
        address token
    ) public view returns (uint256) {
        return s_userCollateralDeposited[msg.sender][token];
    }

    function getDscOfUser(address user) public view returns (uint256) {
        return s_dscMinted[user];
    }

    function getUserCollateralValueInUsd(
        address userAddress
    ) public view returns (uint256 collateralValue) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            collateralValue += getTokenValueInUsd(
                s_tokens[i],
                s_userCollateralDeposited[userAddress][s_tokens[i]]
            );
        }
    }
}
