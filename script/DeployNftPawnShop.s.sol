// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NftPawnShop} from "../src/NftPawnShop.sol";

contract DeployNftPawnShop is Script {
    function run() external returns (NftPawnShop) {
        NftPawnShop nftPawnShop = new NftPawnShop();
        return nftPawnShop;
    }
}
