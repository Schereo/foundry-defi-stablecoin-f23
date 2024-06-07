// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address wethPriceFeed;
    address weth;

    address private USER = makeAddr("USER");
    address private LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant STARTING_WETH_BALANCE = 10 ether;
    uint256 private constant AMOUNT_DSC_TO_MINT = 1000 ether;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10%
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralization

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dscEngine, dsc, helperConfig) = deployDSC.run();
        (wethPriceFeed, , weth, , ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
    }

    /// CONSTRUCTOR TEST ///

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /// PRICE TEST ///

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18;
        // The eth usd price feed is set to ETH_USD_PRICE = 2000e8. Thus, 15 eth * $2000 = $30.0000 USD
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100e18;
        // $2000 USD / 1 ETH = 0.5 ETH
        uint256 expectedWethAmount = 0.05e18;
        uint256 actualWethAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            usdAmount
        );
        assertEq(actualWethAmount, expectedWethAmount);
    }

    /// DEPOSITE COLLATERAL TEST ///

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        bytes memory expectedError = abi.encodeWithSelector(
            DSCEngine.DSCEngine__MustBeMoreThanZero.selector,
            0
        );
        vm.expectRevert(expectedError);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock myUnapprovedToken = new ERC20Mock(
            "Unapproved Token",
            "UT",
            address(this),
            1000
        );
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(myUnapprovedToken), 10);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedTokenAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            totalCollateralValueInUsd
        );
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueInUsd = 20000e18; // 10 ETH * $2000 = $20.0000 USD
        assertEq(totalCollateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(expectedTokenAmount, AMOUNT_COLLATERAL);
    }

    /// MINT DSC TEST ///
    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
    }

    function testRevertMintDscIfHealthFactorBroken()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        uint256 excessiveDscToMint = 40000e18; // Too high for the collateral deposited
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                25e16
            )
        );
        dscEngine.mintDsc(excessiveDscToMint);
        vm.stopPrank();
    }

    /// REDEEM COLLATERAL TEST ///
    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountCollateralToRedeem = 5 ether;
        dscEngine.redeemCollateral(weth, amountCollateralToRedeem);
        (, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(
            USER
        );
        uint256 expectedCollateralValueInUsd = 10000e18; // 5 ETH * $2000 = $10.0000 USD
        assertEq(totalCollateralValueInUsd, expectedCollateralValueInUsd);
        vm.stopPrank();
    }

    function testRevertRedeemCollateralIfHealthFactorBroken()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        uint256 excessiveCollateralToRedeem = 10 ether; // Trying to redeem all collateral
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0
            )
        );
        dscEngine.redeemCollateral(weth, excessiveCollateralToRedeem);
        vm.stopPrank();
    }

    /// BURN DSC TEST ///
    function testBurnDsc() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        // Approve DSCEngine contract to transfer DSC tokens
        dsc.approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDsc(AMOUNT_DSC_TO_MINT);
        (uint256 totalDscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        vm.stopPrank();
    }

}
