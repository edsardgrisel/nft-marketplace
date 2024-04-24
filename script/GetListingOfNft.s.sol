pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {NftPawnShop} from "../src/NftPawnShop.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Nft} from "../test/mock/Nft.sol";

contract GetListingOfNft is Script {
    function run() external {
        NftPawnShop marketplace = NftPawnShop(0x5FbDB2315678afecb367f032d93F642f64180aa3);

        uint256 price = marketplace.getPrice(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, 1);
        console.log("Price: ", price);

        Nft nft = Nft(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);
        console.log("Owner of 1: ", nft.ownerOf(0));
    }
}
