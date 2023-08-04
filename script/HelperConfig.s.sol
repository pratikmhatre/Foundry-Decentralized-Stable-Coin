// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethAddress;
        address wethPriceFeedAddress;
        address wbtcAddress;
        address wbtcPriceFeedAddress;
        uint256 deployerKey;
    }

    NetworkConfig public activNetworkConfig;
    uint8 private DECIMAL = 8;
    int256 private INITIAL_ETH_VALUE = 2000e8;
    int256 private INITIAL_BTC_VALUE = 3000e8;

    constructor() {
        if (block.chainid == 11155111) {
            activNetworkConfig = getSepoliaConfig();
        } else {
            activNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig()
        internal
        view
        returns (NetworkConfig memory config)
    {
        config = NetworkConfig({
            wethAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wethPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcAddress: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            wbtcPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("TESTNET_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig()
        internal
        returns (NetworkConfig memory config)
    {
        if (activNetworkConfig.wethAddress != address(0))
            return activNetworkConfig;

        vm.startBroadcast();
        MockV3Aggregator ethAggregator = new MockV3Aggregator(
            DECIMAL,
            INITIAL_ETH_VALUE
        );
        ERC20Mock ethMock = new ERC20Mock();

        MockV3Aggregator btcAggregator = new MockV3Aggregator(
            DECIMAL,
            INITIAL_BTC_VALUE
        );
        ERC20Mock btcMock = new ERC20Mock();
        vm.stopBroadcast();

        config = NetworkConfig({
            wethAddress: address(ethMock),
            wethPriceFeedAddress: address(ethAggregator),
            wbtcAddress: address(btcMock),
            wbtcPriceFeedAddress: address(btcAggregator),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }
}
