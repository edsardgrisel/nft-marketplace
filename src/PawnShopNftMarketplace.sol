// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PawnShopNftMarketplace {
    constructor() {}

    function listNft(address nftAddress, uint256 tokenId, uint256 price) public {}

    function removeListing(address nftAddress, uint256 tokenId) public {}

    function updateListingPrice(address nftAddress, uint256 tokenId, uint256 price) public {}

    function buyNft(address nftAddress, uint256 tokenId) public payable {}

    //getters and internals

    function getPrice(address nftAddress, uint256 tokenId) public view returns (uint256) {}

    function getAllListedNfts() public view returns (address[] memory, uint256[] memory) {}
}
