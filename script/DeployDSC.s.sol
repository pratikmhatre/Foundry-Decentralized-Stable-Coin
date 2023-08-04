// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] tokens;
    address[] priceFeeds;

    function run()
        external
        returns (DecentralizedStableCoin, DSCEngine, HelperConfig)
    {
        HelperConfig helperConfig = new HelperConfig();

        (
            address wethAddress,
            address wethPriceFeedAddress,
            address wbtcAddress,
            address wbtcPriceFeedAddress,
            uint256 deployerKey
        ) = helperConfig.activNetworkConfig();

        tokens = [wethAddress, wbtcAddress];
        priceFeeds = [wethPriceFeedAddress, wbtcPriceFeedAddress];

        vm.startBroadcast();
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine({
            tokens: tokens,
            priceFeeds: priceFeeds,
            dscAddress: address(dsc)
        });
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine, helperConfig);
    }
}
