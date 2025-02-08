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

    // Our stablecoin contract
    DecentralizedStableCoin private immutable i_dsc;
    // The ERC20 token contract for WETH collateral
    IERC20 private immutable i_weth;
    // The price feed contract for ETH/USD
    AggregatorV3Interface private immutable i_ethUsdPriceFeed;
    // Mapping for tracking collateral balances of users
    mapping(address user => uint256 amount) private s_collateralBalances;

    //Errors
    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSC_EngineTransferFailed();

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

    function depositCollateralAndMintDSC() external {}

    function depositCollateral(
        address _collateralTokenAddress,
        uint256 _collateralAmount
    ) moreThanZero(_collateralAmount) isAllowedToken(_collateralTokenAddress) nonReentrant() external {
        // 1. Update the user's collateral balance in our tracking
        s_collateralBalances[msg.sender] += _collateralAmount;

        // 2. Emit an event to log the deposit
        emit CollateralDeposited(msg.sender, _collateralTokenAddress, _collateralAmount);

        // 3. Transfer the collateral from the user to this contract
        // Note: This contract must be approved to spend the collateral token
        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _collateralAmount);
        if(!success) {
            revert DSC_EngineTransferFailed();
        }
    }

    function redeemCollateralAndBurnDSC() external {}

    function redeemCollateral() external {}

    function mintDSC() external {
    }

    function burnDSC() external {}

    function getHealthFactor() external {}

}