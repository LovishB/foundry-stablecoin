// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
 * @title DSCEngine
 * @author Lovish Badlani
 *
 * The system maintain tokens to 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH.
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 */
contract DSCEngine is ReentrancyGuard {

    //Constants
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18; // 1.0
    uint256 private constant LIQUIDATION_THRESHOLD = 150; // 150%
    uint256 private constant OPTIMAL_COLLATERAL_RATIO = 200; // 200%
    uint256 private constant PERCENTAGE = 100; // 300%
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // Our stablecoin contract
    DecentralizedStableCoin private immutable i_dsc;
    // The ERC20 token contract for WETH collateral
    IERC20 private immutable i_weth;
    // The price feed contract for ETH/USD
    AggregatorV3Interface private immutable i_ethUsdPriceFeed;
    // Mapping for tracking collateral balances of users
    mapping(address user => uint256 amount) private s_collateralBalances;
    // Mapping for tracking DSC balances of users
    mapping(address user => uint256 amount) private s_dscBalances;

    //Errors
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__MintFailed();

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    
    //Modifiers
    modifier moreThanZero(uint256 _amount) {
        if(_amount <= 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if(_token != address(i_weth)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }
    
    //Functions
    constructor(
        address ethUsdPriceFeedAddress,
        address dscAddress,
        address wethAddress
    ) {
        //initialize the price feed contract
        i_ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeedAddress);

        //initialize the stablecoin and WETH token contracts
        i_dsc = DecentralizedStableCoin(dscAddress);
        i_weth = IERC20(wethAddress);
    }

     /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
    * @notice Allows users to deposit WETH collateral to the protocol
    * @dev The collateral is transferred from the user to this contract
    * @dev Emits CollateralDeposited event on successful deposit
    * @dev User must approve this contract to spend their WETH before calling
    * 
    * @param _collateralTokenAddress The address of the collateral token (must be WETH)
    * @param _collateralAmount The amount of collateral to deposit (in wei)
    * 
    * Requirements:
    * - Amount must be greater than 0
    * - Token must be WETH
    * - Transfer must succeed
    * 
    * Emits a {CollateralDeposited} event
    */
    function depositCollateral(
        address _collateralTokenAddress,
        uint256 _collateralAmount
    ) moreThanZero(_collateralAmount) isAllowedToken(_collateralTokenAddress) nonReentrant() public {
        // 1. Update the user's collateral balance in our tracking
        s_collateralBalances[msg.sender] += _collateralAmount;

        // 2. Emit an event to log the deposit
        emit CollateralDeposited(msg.sender, _collateralTokenAddress, _collateralAmount);

        // 3. Transfer the collateral from the user to this contract
        // Note: This contract must be approved to spend the collateral token
        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _collateralAmount);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralAndBurnDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    function liquidate() external {}

    /**
    * @notice Mints DSC tokens for the caller based on their collateral
    * @dev Enforces a 200% collateralization ratio for all mints
    * @dev DSC balance is divided by PRECISION since 1 DSC = 1 USD
    *
    * @param _amountDscToMint Amount of DSC to mint (in wei)
    * 
    * Requirements:
    * - Amount must be greater than 0
    * - User must have enough collateral to mint DSC (200% collateral ratio)
    * 
    * Example:
    * - User has $2000 worth of ETH collateral
    * - Can mint up to 1000 DSC (200% collateral ratio)
    * - If user already has 300 DSC, they can mint 700 more
    */
    function mintDSC(
        uint256 _amountDscToMint
    ) moreThanZero(_amountDscToMint) nonReentrant public {
        // 1. Get the user's collateral balance in USD
        uint256 collateralValue = _getCollateralValueInUsd(msg.sender);

        // 2. Calculate total DSC amount post mint in USD
        uint256 totalDscAmount = (s_dscBalances[msg.sender] + _amountDscToMint) / PRECISION;

        // 3. Check if the user has enough collateral to mint DSC (200%)
        if(collateralValue < (totalDscAmount * OPTIMAL_COLLATERAL_RATIO) / PERCENTAGE) {
            revert DSCEngine__NotEnoughCollateral();
        }

        // 4. Update the user's DSC balance in our tracking
        s_dscBalances[msg.sender] += _amountDscToMint;

        // 5. Mint the DSC tokens to the user
        bool success = i_dsc.mint(msg.sender, _amountDscToMint);
        if(!success) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
    * @notice Reverts if the health factor of a user's position is below the threshold
    * @param user The address of the user to check
    */
    function _revertIfHealthFactorBelowThreshold(address user) private view {
        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBelowThreshold(healthFactor);
        }
    }

    /**
    * @notice Calculates the health factor for a user's position
    * @dev Health factor is the ratio of collateral value to loan value
    * @dev Formula: (collateralValueInUsd * 100) / (dscBalance * 150)
    * @dev DSC balance is divided by PRECISION since 1 DSC = 1 USD
    * @dev _getCollateralValueInUsd returns the USD value of collateral
    *
    * @param user The address of the user to check
    * 
    * Example scenarios (assuming PERCENTAGE = 100, LIQUIDATION_THRESHOLD = 150):
    * - At 150% collateral: returns 1.0 (liquidation point)
    * - At 200% collateral: returns 1.33 (healthy)
    * - At 100% collateral: returns 0.66 (unhealthy)
    */
    function _healthFactor(address user) private view returns (uint256) {
        // 1. Get total DSC balance of the user (1DSC = 1USD)
        uint256 dscBalance = s_dscBalances[user] / PRECISION;
        if(dscBalance == 0) {
            return 0;
        }
        // 2. Get total collateral balance of the user (in USD)
        uint256 collateralBalance = _getCollateralValueInUsd(user);

        // 3. Calculate the health factor
        return collateralBalance * PERCENTAGE / (dscBalance * LIQUIDATION_THRESHOLD);
    }

    /**
    * @notice Converts WETH collateral to USD value using Chainlink price feed
    *
    * @param user The address of the user whose collateral value to check
    * @return uint256 The USD value of the user's collateral
    * 
    * Price conversion process:
    * 1. Get collateral balance in WEI (18 decimals)
    * 2. Get ETH/USD price from Chainlink (8 decimals)
    * 3. Add ADDITIONAL_FEED_PRECISION (10 decimals) for better precision
    * 4. Divide by PRECISION (18 decimals) for final USD value
    */
    function _getCollateralValueInUsd(address user) private view returns (uint256) {
        // 1. Get the user's collateral balance (in WEI)
        uint256 collateralBalance = s_collateralBalances[user];

        // 2. Get the price of 1 WETH in USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // 3. Convert the collateral balance to USD value
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * collateralBalance) / PRECISION;
    }

}