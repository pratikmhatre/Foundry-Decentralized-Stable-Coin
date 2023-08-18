// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    uint256 constant SAFE_UPDATE_WINDOW = 3 hours;

    error OracleLib__StalePriceFeedData();

    function staleCheckLatestRoundData(AggregatorV3Interface aggregator)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint256 answerInRound)
    {
        (roundId, answer, startedAt, updatedAt, answerInRound) = aggregator.latestRoundData();
        uint256 timePassed = block.timestamp - updatedAt;
        if (timePassed > SAFE_UPDATE_WINDOW) revert OracleLib__StalePriceFeedData();
    }
}
