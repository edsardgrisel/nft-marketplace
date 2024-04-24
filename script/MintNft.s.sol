// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Nft} from "../test/mock/Nft.sol";

contract MintNft is Script {
    function run() external {
        uint256 accountOneKey;
        uint256 accountTwoKey;
        uint256 accountThreeKey;
        if (block.chainid == 31337) {
            accountOneKey = vm.envUint("ANVIL_PRIVATE_KEY_ZERO");
            accountTwoKey = vm.envUint("ANVIL_PRIVATE_KEY_ONE");
            accountThreeKey = vm.envUint("ANVIL_PRIVATE_KEY_TWO");
        } else {
            return;
        }

        string memory uri = "ipfs://QmR3PMXfsbc8ePdmYHRbMMthyA3uMN1tjFwkXPPBQJfA3A";

        HelperConfig helperConfig = new HelperConfig();
        Nft nft = Nft(vm.envAddress("ANVIL_NFT_ADDRESS"));
        vm.startBroadcast(accountOneKey);
        for (uint256 i = 0; i < 3; i++) {
            nft.mintNft(uri);
        }
        vm.stopBroadcast();

        vm.startBroadcast(accountTwoKey);
        for (uint256 i = 0; i < 3; i++) {
            nft.mintNft(uri);
        }
        vm.stopBroadcast();

        vm.startBroadcast(accountThreeKey);
        for (uint256 i = 0; i < 3; i++) {
            nft.mintNft(uri);
        }
        vm.stopBroadcast();
    }

    /**
     * @dev Fallback function to receive ETH to test withdrawFees as the owner
     */
    receive() external payable {}
}
