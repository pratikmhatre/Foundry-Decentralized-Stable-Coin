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

contract DSCEngine is ReentrancyGuard {
    //////////////
    ///Errors/////
    //////////////
    error DSCEngine__RequiresAmountGreaterThanZero();
    error DSCEngine__TokenNotSupported();
    error DSC__MintingFailed();
    error DSCEngine__PoorHealthFactor(uint256);

    //////////////
    ///Events/////
    //////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    //////////////////////
    ///State Variables/////
    //////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 balance)) s_userBalances;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_tokens;

    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable i_dsc;

    constructor(
        address[] memory tokens,
        address[] memory priceFeeds,
        address dscAddress
    ) {
        i_dsc = DecentralizedStableCoin(dscAddress);
        for (uint i = 0; i < tokens.length; i++) {
            s_priceFeeds[tokens[i]] = priceFeeds[i];
            s_tokens.push(tokens[i]);
        }
    }

    function depositCollateralAndMintDSC() external {}

    function depositCollateral(
        address tokenAddress,
        uint256 tokenAmount
    )
        external
        onlyAllowedToken(tokenAddress)
        checkAmountGreaterThanZero(tokenAmount)
    {
        s_userBalances[msg.sender][tokenAddress] = tokenAmount;
        emit CollateralDeposited({
            user: msg.sender,
            token: tokenAddress,
            amount: tokenAmount
        });
    }

    function mintDSC(uint256 amount) external nonReentrant {
        s_dscMinted[msg.sender] += amount;
        revertIfHealthFactorBroken(msg.sender);

        bool result = i_dsc.mint(msg.sender, amount);
        if (!result) revert DSC__MintingFailed();
    }

    function redeemCollateralForDSC() external {}

    function burnDSC() external {}

    function liquidateUser() external {}

    function getHealthFactor() external {}

    //////////////
    ///Modifiers//
    //////////////
    modifier onlyAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0))
            revert DSCEngine__TokenNotSupported();
        _;
    }

    modifier checkAmountGreaterThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__RequiresAmountGreaterThanZero();
        _;
    }

    function revertIfHealthFactorBroken(address userAddress) internal view {
        uint256 hf = _calculateHealthFactor(userAddress);
        if (hf < MIN_HEALTH_FACTOR) revert DSCEngine__PoorHealthFactor(hf);
    }

    function _calculateHealthFactor(
        address userAddress
    ) internal view returns (uint256) {
        (uint256 dscMinted, uint256 collateralValueInUsd) = getUserAccountInfo(
            userAddress
        );
        uint256 collateralAdjustedToThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedToThreshold * PRECISION) / dscMinted;
    }

    function getUserAccountInfo(
        address userAddress
    ) public view returns (uint256 dscMinted, uint256 collateralValueInUsd) {
        dscMinted = s_dscMinted[userAddress];
        collateralValueInUsd = _getUserCollateralValueInUsd(userAddress);
    }

    function _getUserCollateralValueInUsd(
        address userAddress
    ) internal view returns (uint256 collateralValue) {
        for (uint256 i = 0; i < s_tokens.length; i++) {
            collateralValue += getTokenValueInUsd(
                s_tokens[i],
                s_userBalances[userAddress][s_tokens[i]]
            );
        }
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
}

// 1 ETH = 200 USD
// 1e18 wei = 200 * 1e8 USD
// 1 wei = (200 * 1e8)/ (1 * 1e18) = 200/1e10
