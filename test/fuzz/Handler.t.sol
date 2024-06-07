// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled = 0;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public wethPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        wethPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    // function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
    //     if (usersWithCollateralDeposited.length == 0) {
    //         return;
    //     }
    //     address sender = usersWithCollateralDeposited[
    //         addressSeed % usersWithCollateralDeposited.length
    //     ];
        
    //     (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
    //         .getAccountInformation(sender);
    //     int256 maxDscToMint = ((int256(collateralValueInUsd) / 2) -
    //         int256(totalDscMinted));
    //     if (maxDscToMint < 0) {
    //         return;
    //     }
    //     amountDsc = bound(amountDsc, 1, uint256(maxDscToMint));
    //     if (amountDsc == 0) {
    //         return;
    //     }
    //     vm.startPrank(sender);
    //     dsc.mint(sender, amountDsc);
    //     vm.stopPrank();
    //     timesMintIsCalled++;
    // }

    function mintAndDepositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
        // Will double push if user already exists in the array
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(
            msg.sender,
            address(collateralToken)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
    }

    function updateCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        wethPriceFeed.updateAnswer(newPriceInt);

    }

    function _getCollateralFromSeed(
        uint256 collateralTokenSeed
    ) private view returns (ERC20Mock) {
        if (collateralTokenSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
