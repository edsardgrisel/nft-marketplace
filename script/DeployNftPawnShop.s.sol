// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NftPawnShop} from "../src/NftPawnShop.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployNftPawnShop is Script {
    function run() external returns (NftPawnShop, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        NftPawnShop nftPawnShop = new NftPawnShop();
        vm.stopBroadcast();

        return (nftPawnShop, helperConfig);
    }

    /**
     * @dev Fallback function to receive ETH to test withdrawFees as the owner
     */
    receive() external payable {}
}
