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
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector,
                3
            )
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
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector,
                2
            )
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
        assertEq(factor, type(uint256).max);
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
        assertEq(factor, 4);
        vm.stopPrank();
    }

    //Tests for burnDSC
    function testBurnDSCRevertsAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector)
        );
        engine.burnDSC(0);
    }

    function testBurnDSCRevertsNotEnoughDSC() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 2000e18);// minted 2000$(2000e18) DSC with 4000$ collateral(2 ether)
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughDSC.selector)
        );
        engine.burnDSC(5000e18);
        vm.stopPrank();
    }

    function testBurnDSCRevertsNoApprovalGivenToEngine() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 2000e18);// minted 2000$(2000e18) DSC with 4000$ collateral(2 ether)
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
                address(engine), // spender
                0,              // current allowance
                2000e18        // requested amount
            )
        );
        engine.burnDSC(2000e18);
        vm.stopPrank();
    }

    function testBurnDSCSuccess() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 4 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 3 ether, 3000e18);
        dsc.approve(address(engine), 2000e18); //approving engine to transfer dsc and then burn eventually

        uint256 userDscBalanceBefore = dsc.balanceOf(user);
        engine.burnDSC(2000e18);

        // Check state changes
        uint256 userDscBalanceAfter = dsc.balanceOf(user);
        uint256 engineTrackedBalanceAfter = engine.getDscBalance(user);

        // Assertions
        assertEq(userDscBalanceAfter, 1000e18, "User's DSC balance should be 1000 after burning");
        assertEq(engineTrackedBalanceAfter, 1000e18, "Engine's tracked DSC balance should be 1000");
        assertEq(userDscBalanceAfter, userDscBalanceBefore - 2000e18, "DSC balance should decrease by burn amount");
        vm.stopPrank();
    }

    //Tests for redeem Collateral
    function testRedeemCollateralRevertsZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector)
        );
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralRevertsInvalidToken() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector)
        );
        engine.redeemCollateral(makeAddr("invalidToken"), 1 ether);
    }

    function testRedeemCollateralRevertsNotEnoughCollateral() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughCollateral.selector)
        );
        engine.redeemCollateral(weth, 1 ether);
    }
    
    function testRedeemCollateralRevertsLowHealthFactor() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        wethMock.approve(address(engine), 2 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 2 ether, 2000e18); //collateral $4000
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorBelowThreshold.selector,
                3
            )
        );
        engine.redeemCollateral(weth, 0.44 ether); //Health Factor < 4
        vm.stopPrank();
    }

    function testRedeemCollateralSuccessful() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);
        uint256 userCollateralBalanceBefore = 3 ether;

        wethMock.approve(address(engine), userCollateralBalanceBefore);
        engine.depositCollateralAndMintDsc(address(wethMock), userCollateralBalanceBefore, 2000e18); //collateral $6000, dsc 2000$
        engine.redeemCollateral(weth, 1 ether); //Health Factor = 4

        // Check state changes
        uint256 userCollateralBalanceAfter = engine.getCollateralBalance(user);

        // Assertions
        assertEq(userCollateralBalanceAfter, 2 ether, "User's Collateral balance should be 4000 after redeem");
        assertEq(userCollateralBalanceAfter, userCollateralBalanceBefore - 1 ether, "DSC Collateral should decrease by redeem amount");
        vm.stopPrank();
    }


    //Test for burn and redeem collateral
    function testBurnDSCAndRedeemCollateralSuccessful() public {
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        ERC20Mock wethMock = ERC20Mock(weth);
        wethMock.mint(user, 10 ether);

        wethMock.approve(address(engine), 4 ether);
        engine.depositCollateralAndMintDsc(address(wethMock), 4 ether, 2000e18); //collateral $8000, dsc 2000$

        dsc.approve(address(engine), 1500e18); //approving engine to burn 1500$ worth dsc
        engine.redeemCollateralAndBurnDSC(weth, 3 ether, 1500e18);//burning 1500$ dsc and redeem $6000 weth

        // Check state changes
        uint256 userCollateralBalanceAfter = engine.getCollateralBalance(user);

        // Assertions
        assertEq(userCollateralBalanceAfter, 1 ether, "User's Collateral balance should be 1000 after redeem");
        vm.stopPrank();
    }


}