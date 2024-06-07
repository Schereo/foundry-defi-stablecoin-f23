// // SPDX-License-Identifier: MIT

// // What are the invariants that should always hold true?
// // 1. The total supply of DCS should always be less or equal to the value in Dollar of the collateral deposited.
// // 2. Getter view functions should never revert

// pragma solidity 0.8.19;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DSCEngine dscEngine;
//     DecentralizedStableCoin dsc;
//     DeployDSC deployDSC;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployDSC = new DeployDSC();
//         (dscEngine, dsc, config) = deployDSC.run();
//         (, ,weth, wbtc , ) = config.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalDscSupply = dsc.totalSupply();

//         uint256 wethTokensDeposited = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 wbtcTokensDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

//         uint256 wethValue = dscEngine.getUsdValue(weth, wethTokensDeposited);
//         uint256 wbtcValue = dscEngine.getUsdValue(wbtc, wbtcTokensDeposited);

//         uint256 totalCollateralValue = wethValue + wbtcValue;

//         // Total DSC supply should be less or equal to the total value of the collateral deposited
//         assert(totalDscSupply <= totalCollateralValue);
//     }


// }
