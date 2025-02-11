// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";


contract HelperConfig is Script {

    uint8 public constant MOCK_DECIMALS = 8;
    int256 public constant INITIAL_MOCK_PRICE = 2000e8;

    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        uint256 deployerKey;
        string rpcUrl;
        address priceFeed;
        address weth;
    }

    constructor() {
        if (block.chainid == 1) {
            activeNetworkConfig = getMainnetEthConfig();
        } else if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("PRIVATE_KEY"),
            rpcUrl: vm.envString("MAINNET_RPC_URL"),
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            deployerKey: vm.envUint("PRIVATE_KEY"),
            rpcUrl: vm.envString("SEPOLIA_RPC_URL"),
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            weth: 0x6B175474E89094C44Da98b954EedeAC495271d0F
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        //first check if we already deplyed anvil price feed mock or not
        if(activeNetworkConfig.priceFeed != address(0)) { 
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator( //this is for mocking price feed in local testing
            MOCK_DECIMALS, // decimals
            INITIAL_MOCK_PRICE // initial answer
        );
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8); //Mock for Weth
        vm.stopBroadcast();
        return NetworkConfig({
            deployerKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
            rpcUrl: "http://localhost:8545",
            priceFeed: address(mockPriceFeed),
            weth: address(wethMock)
        });
    }

}