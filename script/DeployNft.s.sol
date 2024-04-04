// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Nft} from "../test/mock/Nft.sol";

contract DeployNft is Script {
    function run() external returns (Nft) {
        HelperConfig helperConfig = new HelperConfig();
        (uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        Nft nftProjectOne = new Nft("Project One", "P1");
        vm.stopBroadcast();

        return (nftProjectOne);
    }

    /**
     * @dev Fallback function to receive ETH to test withdrawFees as the owner
     */
    receive() external payable {}
}
