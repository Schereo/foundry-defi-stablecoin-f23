// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Tim Sigl
 * @notice This library checks the Chainlink price feed Oracles for stale data
 * If a price is stale, the function will revert, rendering the DSCEngine contract unusable, this is by design
 *
 * This will freeze all funds if the chainlink network goes down
 */
library OracleLib {
    error OracleLib__StalePrice(uint256 timeSinceUpdate);

    uint256 constant TIMEOUT = 3 hours;

    function staleCheckLastestRoundData(
        AggregatorV3Interface _priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = _priceFeed.latestRoundData();

        uint256 timeSinceUpdate = block.timestamp - updatedAt;

        if (timeSinceUpdate > TIMEOUT) {
            revert OracleLib__StalePrice(timeSinceUpdate);
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
