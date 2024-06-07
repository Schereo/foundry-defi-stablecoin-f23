// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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

pragma solidity 0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {OracleLib} from "./OracleLib.sol";

/**
 * @title DSCEngine
 * @author Tim Sigl
 * @notice This engine is designed to be as simple as possible. It maintains a 1:1 peg with the USD.
 * It is designed to be:
 * - Collateral: Exogenous
 * - Minting (Stability Mechanism): Decentralized (Algorithmic)
 * - Value (Relative Stability): Anchored (Pegged to USD)
 * - Collateral Type: Crypto
 *
 * The system is designed to be "overcollateralized" to ensure that the DSC token is always backed by more
 * than 100% of the collateral wBTC and wETH.
 *
 * @notice This contract is the core of the DSC system. It is responsible for minting and burning DSC tokens.
 * @notice It is very loosely based on the MakerDAO system with the DAI token.
 */
contract DSCEngine is ReentrancyGuard {
    /// ERRORS ///
    error DSCEngine__MustBeMoreThanZero(uint256 amount);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /// TYPES /// 
    using OracleLib for AggregatorV3Interface;

    /// STATE VARIABLES ///
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // Minimum overcollateralization of 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUADATION_BONUS = 10; // 10% bonus the liquidator gets for liquidating a user

    mapping(address token => address priceFeed) s_tokenToPriceFeed;
    mapping(address user => mapping(address token => uint256 amount)) s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) s_dscMinted;

    address[] private collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    /// EVENTS ///

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /// MODIFIERS ///

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert DSCEngine__MustBeMoreThanZero(amount);
        _;
    }

    modifier isAllowedCollateral(address token) {
        if (s_tokenToPriceFeed[token] == address(0))
            revert DSCEngine__TokenNotAllowed();
        _;
    }

    /// FUNCTIONS ///

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /// EXTERNAL & PUBLIC FUNCTIONS ///

    /**
     *
     * @param tokenCollateralAddress The address of the token deposited as collateral
     * @param collateralAmount The amount of collateral tokens to deposite
     * @param amountDscToMint The amount of decentralized stable coin tokens to mint
     * @notice This function will deposite the users collateral and mint DSC tokens for the user in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(amountDscToMint);
    }

    /**
     *
     * @param tokenCollateralAddress the address of the token deposited as collateral
     * @param collateralAmount the amount of the token deposited as collateral
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 collateralAmount
    )
        public
        moreThanZero(collateralAmount)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += collateralAmount;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            collateralAmount
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the collateral token to redeem
     * @param amountCollateral  The amount of collateral to redeem
     * @param dscAmountToBurn The amount of DSC tokens to burn
     * @notice This function will burn the users DSC tokens and redeem the collateral they previously put in one transaction
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 dscAmountToBurn
    ) external {
        burnDsc(dscAmountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mint decentralized stable coin tokens
     * @param amountDscToMint the amount of decentralized stable coin tokens to mint
     * @notice Users must have more collateral than the the minimum collateral threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // There should never be the case where removing DSC tokens breaks the health factors
    }

    /**
     * @notice Lets a user liquidate another user to ensure stability of the coin
     * @param collateralToken The collateral token to liquidate
     * @param userToLiquidate  The user to liquidate who has a health factor below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC tokens
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for liquidating a user to incentivize liquidations
     * @notice Liquidation only works if the protocol is overcollateralized. For the case that
     * 1 DSC (debt) >= 1 USD collateral tokens, no one would pay somebodies debt because they would lose money (e.g. paying $1 DSC dept to get $0.8 collateral tokens)
     */
    function liquidate(
        address collateralToken,
        address userToLiquidate,
        uint256 debtToCover
    )
        external
        moreThanZero(debtToCover)
        isAllowedCollateral(collateralToken)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(userToLiquidate);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // We want to burn the users DSC tokens (debt) and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateralToken,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUADATION_BONUS) * LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateralToken,
            totalCollateralToRedeem,
            userToLiquidate,
            msg.sender
        );
        _burnDsc(debtToCover, userToLiquidate, msg.sender);

        // Check that the user's health factor has improved
        uint256 endingUserHealthFactor = _healthFactor(userToLiquidate);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        // Revert if the liquidator's health factor is broken after the liquidation
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    /// PUBLIC & EXTERNAL VIEW FUNCTIONS ///

    function getTokenAmountFromUsd(
        address collateralToken,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeed[collateralToken]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLastestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            // uint256 price = IPriceFeed(s_tokenToPriceFeed[token]).getPrice();
            totalCollateralValueInUsd += getUsdValue(token, collateralAmount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeed[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLastestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return collateralTokens;
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_tokenToPriceFeed[token];
    }

    function getCollateralBalanceOfUser(
        address user,
        address collateralToken
    ) external view returns (uint256) {
        return s_collateralDeposited[user][collateralToken];
    }

    /// PRIVATE & INTERNAL VIEW FUNCTIONS ///

    /**
     * @dev low-level internal function, do not call unless calling functions performs health factor check
     */
    function _burnDsc(
        uint256 amount,
        address onBehalfOf,
        address from
    ) private moreThanZero(amount) {
        s_dscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(from, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        // Emit event
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        // Transfer collateral back to user
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(user);

        return (totalDscMinted, totalCollateralValueInUsd);
    }

    /**
     * @notice Returns how close to liquidation the user is
     * @notice Users with a health factor below 1 are in danger of being liquidated
     * @param user the address of the user
     * @return the health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        //40000000000000000000000 totalDscMinted
        //20000000000000000000000 collateralValueInUsd
        //10000000000000000000000 collateralAdjustedForThreshold
        console.log("totalDscMinted: %s", totalDscMinted);
        console.log("collateralValueInUsd: %s", collateralValueInUsd);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        console.log(
            "collateralAdjustedForThreshold: %s",
            collateralAdjustedForThreshold
        );
        if (totalDscMinted == 0) {
            return (collateralAdjustedForThreshold * PRECISION);
        }

        uint256 healthFactor = (collateralAdjustedForThreshold * PRECISION) /
            totalDscMinted;
        console.log("healthFactor: %s", healthFactor);
        return healthFactor;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        console.log("userHealthFactor: %s", userHealthFactor);
        console.log("MIN_HEALTH_FACTOR: %s", MIN_HEALTH_FACTOR);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
}
