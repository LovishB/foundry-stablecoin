// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { DeployDSC } from "../script/DeployDSC.s.sol";
import { HelperConfig } from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address user;
    address weth;
    address priceFeed;

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, engine, helperConfig) = deployDSC.run();
        (,, address _pricefeed,address _weth) = helperConfig.activeNetworkConfig();
        weth = _weth;
        priceFeed = _pricefeed;
        user = makeAddr("user");
    }

    function testContractInitializesCorrectly() public view {
        assertEq(dsc.owner(), address(engine));
        assertEq(engine.getDscAddress(), address(dsc));
        assertEq(engine.getEthUsdPriceFeedAddress(), priceFeed);
        assertEq(engine.getWethAddress(), weth);
    }


    // Tests for deposit collateral
    function testDepositCollateralRevertsAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector)
        );
        engine.depositCollateral(weth, 0);
    }

    function testDepositCollateralRevertsInvalidToken() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector)
        );
        engine.depositCollateral(makeAddr("invalidToken"), 1 ether);
    }

    function testDepositCollateralRevertsTokensNotApproved() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        //user should have 1 weth tokens so minting 1 weth
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
                address(engine), // spender
                0,              // current allowance
                1 ether        // requested amount
            )
        );
        engine.depositCollateral(address(wethMock), 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateralSuccessfully() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        //user should have 1 weth tokens so minting 1 weth
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        
        // user should allow engine to spend 1 weth
        wethMock.approve(address(engine), 1 ether);

        engine.depositCollateral(address(wethMock), 1 ether);
        vm.stopPrank();

        assertEq(engine.getCollateralBalance(user), 1 ether);
        assertEq(wethMock.balanceOf(address(engine)), 1 ether);
        assertEq(wethMock.balanceOf(user), 9 ether);
    }

    // Tests for minting DSC
    function testMintDSCRevertsAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector)
        );
        engine.mintDSC(0);
    }

    function testMintDSCRevertsNotEnoughCollateral() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        // deposit 2 WETH as collateral
        uint256 collateralAmount = 2 ether; // 2e18 WETH
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 5 ether);
        wethMock.approve(address(engine), collateralAmount);
        engine.depositCollateral(address(wethMock), collateralAmount);

        // First calculate collateral value in USD: (2e18 * 2000e8 * 1e10) / 1e18 = 4000e18
        uint256 collateralValueInUsd = (collateralAmount * uint256(helperConfig.INITIAL_MOCK_PRICE()) * 1e10) / 1e18;

        // minting 2001 DSC
        uint256 DSCToMint = (collateralValueInUsd / 2) + 1e18;

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughCollateral.selector)
        );
        engine.mintDSC(DSCToMint);
        vm.stopPrank();
    }

    function testMintDSCSuccessful() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        // deposit 2 WETH as collateral
        uint256 collateralAmount = 2 ether; // 2e18 WETH
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 5 ether);
        wethMock.approve(address(engine), collateralAmount);
        engine.depositCollateral(address(wethMock), collateralAmount);

        // First calculate collateral value in USD: (2e18 * 2000e8 * 1e10) / 1e18 = 4000e18
        uint256 collateralValueInUsd = (collateralAmount * uint256(helperConfig.INITIAL_MOCK_PRICE()) * 1e10) / 1e18;
        // minting 1999 DSC
        uint256 DSCToMint = (collateralValueInUsd / 2) - 1e18;

        engine.mintDSC(DSCToMint);
        assertEq(engine.getDscBalance(user), DSCToMint);
        assertEq(dsc.balanceOf(user), DSCToMint);
        vm.stopPrank();
    }

    // Tests for deposit Collateral AndMint
    function testDepositCollateralAndMintRevertsCollateralFails() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        //Not approved engine to spend 2 WETH
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
                address(engine), // spender
                0,              // current allowance
                2 ether        // requested amount
            )
        ); 
        engine.depositCollateralAndMintDsc(weth, 2 ether, 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintRevertsMintFails() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughCollateral.selector)
        );
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 3000e18); // minting DSC more than possible
        vm.stopPrank();
    }

    function testDepositCollateralAndMintSuccess() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 2000e18);
        assertEq(engine.getCollateralBalance(user), 2 ether);
        assertEq(engine.getDscBalance(user), 2000e18);
        vm.stopPrank();
    }

    // Test for Health Factor
    function testHealthFactorZeroDSCBalance() public {
        vm.startPrank(user);
        uint256 factor = engine.getHealthFactor(user);
        assertEq(factor, 0);
        vm.stopPrank();
    }

    function testHealthFactorHealthy() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 2000e18); //200% collateralization
        uint256 factor = engine.getHealthFactor(user);
        assertEq(factor, 1);
        vm.stopPrank();
    }

}