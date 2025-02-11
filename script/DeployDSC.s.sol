// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey, , address priceFeed, address weth) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(priceFeed, address(dsc), weth);
        dsc.transferOwnership(address(engine)); // making the engine owner for dsc contract
        vm.stopBroadcast();
        return (dsc, engine, helperConfig);
    }
}