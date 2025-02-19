// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";

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
    error DSCEngine__NotEnoughDSC();
    error DSCEngine__MintFailed();
    error DSCEngine__BurnFailed();

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
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will burn DSC and redeem your collateral in one transaction
     */
    function redeemCollateralAndBurnDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
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
        // 1. Update the user's DSC balance and then check health factor, if not >4 revert
        s_dscBalances[msg.sender] += _amountDscToMint;
    
        // 2. Check if health factor remains >= 4 (200% collateralization)
        if(_healthFactor(msg.sender) < 4) {
            revert DSCEngine__HealthFactorBelowThreshold(_healthFactor(msg.sender));
        }

        // 3. Mint the DSC tokens to the user
        bool success = i_dsc.mint(msg.sender, _amountDscToMint);
        if(!success) {
            s_dscBalances[msg.sender] -= _amountDscToMint; // Restore the state if mint fails
            revert DSCEngine__MintFailed();
        }
    }

    /**
    * @notice Allows users to withdraw their WETH collateral from the protocol
    * @dev User's health factor must remain >= 4 (200% collateralization) after withdrawal
    * 
    * @param _collateralTokenAddress The address of the collateral token (must be WETH)
    * @param _collateralAmount The amount of collateral to withdraw (in wei)
    * 
    * Requirements:
    * - Amount must be greater than 0
    * - Token must be WETH and user must have sufficient collateral balance
    * - Withdrawal must maintain 200% collateral ratio (health factor >= 4)
    *
    * Example:
    * - User has 200 USD of ETH collateral and 50 DSC debt
    * - Can withdraw up to 100 USD of ETH while maintaining 200% ratio
    */
    function redeemCollateral(
        address _collateralTokenAddress,
        uint256 _collateralAmount
    ) moreThanZero(_collateralAmount) isAllowedToken(_collateralTokenAddress) nonReentrant() public {
        // 1. Check if the user has enough collateral to redeem
        if(s_collateralBalances[msg.sender] < _collateralAmount) {
            revert DSCEngine__NotEnoughCollateral();
        }

        // 2. Update the user's collatral balance and then check health factor, if not >4 revert (200% collateral ratio)
        s_collateralBalances[msg.sender] -= _collateralAmount;
        if(_healthFactor(msg.sender) < 4) {
            revert DSCEngine__HealthFactorBelowThreshold(_healthFactor(msg.sender));
        }

        // 3. Transfer the collateral from this contract to the user
        bool success = IERC20(_collateralTokenAddress).transfer(msg.sender, _collateralAmount);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
    * @notice Burns DSC tokens to reduce user's debt position in the protocol
    * @dev No health factor check needed as burning DSC always improves the position
    *
    * @param _amountDscToBurn Amount of DSC to burn (in wei)
    * 
    * Requirements:
    * - Amount must be greater than 0
    * - User must have enough DSC balance to burn
    * - User must have approved this contract to burn their DSC
    * 
    * Example:
    * - User has $2000 worth of ETH collateral and 1000 DSC debt
    * - Burns 500 DSC, reducing debt to 500 DSC
    * - Collateralization ratio improves from 200% to 400%
    */
    function burnDSC(
        uint256 _amountDscToBurn
    ) moreThanZero(_amountDscToBurn) nonReentrant public {
        // 1. Check if the user has enough DSC to burn
        console.log(s_dscBalances[msg.sender]);
        console.log(_amountDscToBurn);
        if(s_dscBalances[msg.sender] < _amountDscToBurn) {
            revert DSCEngine__NotEnoughDSC();
        }

        // 2. Update uers's DSC balance
        s_dscBalances[msg.sender] -= _amountDscToBurn;

        // 3. Transfer DSC tokens from user to engine for burning
        bool transferSuccess = i_dsc.transferFrom(msg.sender, address(this), _amountDscToBurn);
        if(!transferSuccess) {
            revert DSCEngine__TransferFailed();
        }

        // 3. Burning the DSC tokens
        // No need to check health factor as DSC burning improves the health factor and manages collateral
        i_dsc.burn(_amountDscToBurn);
    }

    function liquidate() external {}

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
    * - At 150% collateral: returns 3 (liquidation point)
    * - At 200% collateral: returns 4 (healthy)
    * - At 100% collateral: returns 2 (unhealthy)
    * - At 0% collateral: returns 0 (liquidated)
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
        return collateralBalance * 2 / (dscBalance);
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
        uint256 collateralBalance = s_collateralBalances[user] / PRECISION;

        // 2. Get the price of 1 WETH in USD
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // 3. Convert the collateral balance to USD value
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * collateralBalance) / PRECISION;
    }


    // Getter Functions
    function getCollateralBalance(address user) external view returns (uint256) {
        return s_collateralBalances[user];
    }

    function getDscBalance(address user) external view returns (uint256) {
        return s_dscBalances[user];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getWethAddress() external view returns (address) {
        return address(i_weth);
    }

    function getEthUsdPriceFeedAddress() external view returns (address) {
        return address(i_ethUsdPriceFeed);
    }

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }

}