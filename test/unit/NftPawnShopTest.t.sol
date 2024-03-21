// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Test, console} from "forge-std/Test.sol";
import {NftPawnShop} from "../../src/NftPawnShop.sol";
import {DeployNftPawnShop} from "../../script/DeployNftPawnShop.s.sol";
import {Nft} from "../mock/Nft.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract NftPawnShopTest is StdCheats, Test {
    uint256 constant USER_STARTING_AMOUNT = 100 ether;
    uint256 constant NFT_PRICE = 10 ether;
    address userA = makeAddr("userA");
    address userB = makeAddr("userB");
    uint256 userANftId = 0;
    uint256 userBNftId = 1;
    Nft nft;
    NftPawnShop nftPawnShop;
    DeployNftPawnShop deployNftPawnShop;

    modifier userAListedNft() {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();
        _;
    }

    modifier usersDeposited() {
        vm.startPrank(userA);
        nftPawnShop.deposit{value: USER_STARTING_AMOUNT}();
        vm.stopPrank();

        vm.startPrank(userB);
        nftPawnShop.deposit{value: USER_STARTING_AMOUNT}();
        vm.stopPrank();
        _;
    }
    /**
     * @notice Test setup
     * @dev Deploy the conract. If we are on a local chain, deal some ether to the users and mint one nft per user.
     */

    function setUp() external {
        deployNftPawnShop = new DeployNftPawnShop();
        nftPawnShop = deployNftPawnShop.run();

        if (block.chainid == 31337) {
            vm.deal(userA, USER_STARTING_AMOUNT);
            vm.deal(userB, USER_STARTING_AMOUNT);

            nft = new Nft();
            vm.prank(userA);
            nft.mintNft("uriA");
            vm.prank(userB);
            nft.mintNft("uriB");
        } else {
            // @note: deploy the contract on sepolia
        }
    }

    //----Constructor Tests----//
    function testConstructor() public {
        assertEq(nftPawnShop.owner(), address(deployNftPawnShop));
    }

    //----onErc721Received Tests----//
    function testContractCanReceiveErc721() public {
        vm.prank(userA);
        nft.approve(address(this), userANftId);
        nft.safeTransferFrom(userA, address(nftPawnShop), userANftId);
    }

    //----listNft Tests----//
    function testListNft() public {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();
        assertEq(nftPawnShop.getPrice(address(nft), userANftId), 10 ether);
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), userA);
    }

    // Approval fails as the contract own the nft and no user a.
    // List fails as user a is not the owner of the nft.
    // Line in listNft with safe transfer will also just fail as the user is not owner.
    function testListAlreadyListedNft() public userAListedNft {
        vm.startPrank(userA);
        vm.expectRevert();
        nft.approve(address(nftPawnShop), userANftId);
        vm.expectRevert();
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();
    }

    function testListAlreadyListedNftAsContract() public userAListedNft {
        vm.startPrank(address(nftPawnShop));
        nft.approve(address(nftPawnShop), userANftId);
        vm.expectRevert(
            abi.encodeWithSelector(NftPawnShop.NftPawnShop__NftAlreadyListed.selector, address(nft), userANftId)
        );
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE + 1);
        vm.stopPrank();
    }

    function testListWithZeroPrice() public {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.listNft(address(nft), userANftId, 0);
    }

    function testListWithZeroAddress() public {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.listNft(address(0), userANftId, NFT_PRICE);
    }

    function testListAsNonNftOwner() public {
        vm.startPrank(userA);
        vm.expectRevert();
        nft.approve(address(nftPawnShop), userBNftId);
        vm.expectRevert();
        nftPawnShop.listNft(address(nft), userBNftId, NFT_PRICE);
    }

    //----removeListing Tests----//

    function testRemoveListing() public userAListedNft {
        vm.startPrank(userA);
        nftPawnShop.removeListing(address(nft), userANftId);
        vm.stopPrank();
        assertEq(nftPawnShop.getPrice(address(nft), userANftId), 0);
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), address(0));
    }

    function testRemoveListingAsNonOwner() public userAListedNft {
        vm.startPrank(userB);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeOwner.selector);
        nftPawnShop.removeListing(address(nft), userANftId);
        vm.stopPrank();
    }

    function testRemoveListingZeroAddress() public userAListedNft {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.removeListing(address(0), userANftId);
        vm.stopPrank();
    }

    function testRemoveListingThatIsNotListed() public {
        vm.startPrank(userA);
        vm.expectRevert();
        nftPawnShop.removeListing(address(nft), userANftId);
        vm.stopPrank();
    }

    //----updateListingPrice Tests----//

    function testUpdateListingPrice() public userAListedNft {
        vm.startPrank(userA);
        nftPawnShop.updateListingPrice(address(nft), userANftId, NFT_PRICE + 1);
        vm.stopPrank();
        assertEq(nftPawnShop.getPrice(address(nft), userANftId), NFT_PRICE + 1);
    }

    function testUpdateListingPriceAsNonOwner() public userAListedNft {
        vm.startPrank(userB);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeOwner.selector);
        nftPawnShop.updateListingPrice(address(nft), userANftId, NFT_PRICE + 1);
        vm.stopPrank();
    }

    function testUpdateListingPriceZeroAddress() public userAListedNft {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.updateListingPrice(address(0), userANftId, NFT_PRICE + 1);
        vm.stopPrank();
    }

    function testUpdateListingPriceZeroPrice() public userAListedNft {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.updateListingPrice(address(nft), userANftId, 0);
        vm.stopPrank();
    }

    function testUpdateListingPriceThatIsNotListed() public {
        vm.startPrank(userA);
        vm.expectRevert();
        nftPawnShop.updateListingPrice(address(nft), userANftId, NFT_PRICE + 1);
        vm.stopPrank();
    }

    //----buyNft Tests----//

    function testBuyNftSucceedsAndTakesFee() public userAListedNft usersDeposited {
        uint256 fee = NFT_PRICE / 100;
        vm.startPrank(userB);
        nftPawnShop.buyNft(address(nft), userANftId);
        vm.stopPrank();

        assertEq(nftPawnShop.getPrice(address(nft), userANftId), 0);
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), address(0));
        assertEq(nftPawnShop.getBalance(userB), USER_STARTING_AMOUNT - NFT_PRICE);
        assertEq(nftPawnShop.getBalance(userA), USER_STARTING_AMOUNT + NFT_PRICE - fee);
        assertEq(address(nftPawnShop).balance - (nftPawnShop.getBalance(userA) + nftPawnShop.getBalance(userB)), fee);
        assertEq(nft.ownerOf(userANftId), userB);
    }

    function testBuyNftAsNonListed() public usersDeposited {
        vm.startPrank(userB);
        vm.expectRevert();
        nftPawnShop.buyNft(address(nft), userANftId);
        vm.stopPrank();
    }

    function testBuyOwnNft() public userAListedNft usersDeposited {
        vm.startPrank(userA);
        nftPawnShop.buyNft(address(nft), userANftId);
        vm.stopPrank();
        uint256 fee = NFT_PRICE / 100;
        assertEq(nftPawnShop.getBalance(userA), USER_STARTING_AMOUNT - fee);
    }

    //----deposit Tests----//

    function testDeposit() public {
        vm.startPrank(userA);
        nftPawnShop.deposit{value: 10 ether}();
        vm.stopPrank();
        assertEq(nftPawnShop.getBalance(userA), 10 ether);
        assertEq(address(nftPawnShop).balance, 10 ether);
    }

    function testDepositZero() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.deposit{value: 0}();
        vm.stopPrank();
    }

    //----withdraw Tests----//

    function testWithdraw() public usersDeposited {
        vm.startPrank(userA);
        nftPawnShop.withdraw(10 ether);
        vm.stopPrank();
        assertEq(nftPawnShop.getBalance(userA), USER_STARTING_AMOUNT - 10 ether);
        assertEq(address(nftPawnShop).balance, 2 * USER_STARTING_AMOUNT - 10 ether);
        assertEq(address(userA).balance, 10 ether);
    }

    function testWithdrawMoreThanBalance() public usersDeposited {
        vm.startPrank(userA);
        nftPawnShop.withdraw(2 * USER_STARTING_AMOUNT);
        vm.stopPrank();
        assertEq(nftPawnShop.getBalance(userA), 0);
        assertEq(address(nftPawnShop).balance, USER_STARTING_AMOUNT);
        assertEq(address(userA).balance, USER_STARTING_AMOUNT);
    }

    function testWithdrawZero() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.withdraw(0);
        vm.stopPrank();
    }

    //----getPrice Tests----//

    function testGetPrice() public userAListedNft {
        assertEq(nftPawnShop.getPrice(address(nft), userANftId), NFT_PRICE);
    }

    function testGetPriceNotListed() public {
        assertEq(nftPawnShop.getPrice(address(nft), userANftId), 0);
    }

    //----getOwner Tests----//

    function testGetOwner() public userAListedNft {
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), address(userA));
    }

    function testGetOwnerNotListed() public {
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), address(0));
    }

    //----getBalance Tests----//

    function testGetBalance() public usersDeposited {
        assertEq(nftPawnShop.getBalance(userA), USER_STARTING_AMOUNT);
    }

    //----One off tests----//

    function testOneBigTest() public userAListedNft usersDeposited {
        vm.startPrank(userA);
        nftPawnShop.withdraw(10 ether); // userA balance = 90
        nftPawnShop.removeListing(address(nft), userANftId);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();

        vm.deal(userB, 100 ether);
        vm.startPrank(userB);
        nftPawnShop.deposit{value: 100 ether}(); // userB balance = 200
        vm.stopPrank();

        //user b buys user a nft
        vm.startPrank(userB);
        nftPawnShop.buyNft(address(nft), userANftId); // userA balance = 90 + 10 - 0.1 = 99.9, userB balance = 200 - 10
        vm.stopPrank();

        //user b lists nft
        vm.startPrank(userB);
        nft.approve(address(nftPawnShop), userBNftId);
        nftPawnShop.listNft(address(nft), userBNftId, NFT_PRICE);
        nftPawnShop.updateListingPrice(address(nft), userBNftId, NFT_PRICE * 2);
        vm.stopPrank();

        //user a buys user b nft
        vm.startPrank(userA);
        nftPawnShop.buyNft(address(nft), userBNftId); // userA balance = 99.9 - 20 = 79.9, userB balance = 200 + 20
        vm.stopPrank();

        //user b withdraws all funds
        vm.startPrank(userB);
        nftPawnShop.withdraw(200 ether);
        vm.stopPrank();

        assertEq(nftPawnShop.getBalance(userA), 79.9 ether);
        assertEq(nftPawnShop.getBalance(userB), 9.8 ether);
        assertEq(nft.ownerOf(userANftId), userB);
        assertEq(nft.ownerOf(userBNftId), userA);
    }
}
