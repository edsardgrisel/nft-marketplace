// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Test, console} from "forge-std/Test.sol";
import {NftPawnShop} from "../../src/NftPawnShop.sol";
import {DeployNftPawnShop} from "../../script/DeployNftPawnShop.s.sol";
import {DeployNft} from "../../script/DeployNft.s.sol";
import {Nft} from "../mock/Nft.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract NftPawnShopTest is StdCheats, Test {
    struct PawnRequest {
        address borrower;
        address nftAddress;
        uint256 tokenId;
        uint256 loanAmount;
        uint256 loanDuration;
        uint256 interestRate;
    }

    struct PawnAgreement {
        address borrower;
        address lender;
        address nftAddress;
        uint256 tokenId;
        uint256 loanAmount;
        uint256 loanDuration;
        uint256 interestRate;
        uint256 startTime;
        uint256 endTime;
        bool paidBackOrForeclosed;
    }

    uint256 constant USER_STARTING_AMOUNT = 100 ether;
    uint256 constant NFT_PRICE = 10 ether;
    address userA = makeAddr("userA");
    address userB = makeAddr("userB");
    uint256 userANftId = 0;
    uint256 userBNftId = 1;
    Nft nft;
    NftPawnShop nftPawnShop;
    DeployNftPawnShop deployNftPawnShop;
    DeployNft deployNft;
    HelperConfig helperConfig;
    address ownerAddress;

    modifier userAListedNft() {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();
        _;
    }

    modifier userAHasRequestedPawn() {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.requestPawn(address(nft), userANftId, 1 ether, 1 days, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();
        _;
    }

    modifier userARequestedAndUserBApprovedPawn() {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.requestPawn(address(nft), userANftId, 1 ether, 1 days, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();

        vm.startPrank(userB);
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();
        _;
    }

    modifier userAHasBalance() {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(userB);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();
        _;
    }

    /**
     * @notice Test setup
     * @dev Deploy the conract. If we are on a local chain, deal some ether to the users and mint one nft per user.
     */
    function setUp() external {
        deployNftPawnShop = new DeployNftPawnShop();
        (nftPawnShop, helperConfig) = deployNftPawnShop.run();

        deployNft = new DeployNft();
        nft = deployNft.run();
        if (block.chainid == 31337) {
            vm.deal(userA, USER_STARTING_AMOUNT);
            vm.deal(userB, USER_STARTING_AMOUNT);

            nft = new Nft("Nft", "NFT");
            vm.prank(userA);
            nft.mintNft("uriA");
            vm.prank(userB);
            nft.mintNft("uriB");
            ownerAddress = vm.envAddress("ANVIL_PUBLIC_KEY_ZERO");
        } else {
            // @note: deploy the contract on sepolia
        }
    }

    //----Constructor Tests----//

    function testConstructor() public {
        assertEq(nftPawnShop.owner(), ownerAddress);
    }

    //----onErc721Received Tests----//

    function testContractCanReceiveErc721() public {
        vm.prank(userA);
        nft.approve(address(this), userANftId);
        nft.safeTransferFrom(userA, address(nftPawnShop), userANftId);
    }

    //----requestPawn Tests----//

    function testRequestPawn() public {
        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.requestPawn(address(nft), userANftId, 1 ether, 1 days, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();
        PawnRequest memory pawnRequest = PawnRequest({
            borrower: userA,
            nftAddress: address(nft),
            tokenId: userANftId,
            loanAmount: 1 ether,
            loanDuration: 1 days,
            interestRate: 1e17
        });
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).borrower, pawnRequest.borrower);
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).nftAddress, pawnRequest.nftAddress);
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).tokenId, pawnRequest.tokenId);
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).loanAmount, pawnRequest.loanAmount);
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).loanDuration, pawnRequest.loanDuration);
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).interestRate, pawnRequest.interestRate);
    }

    function testRequestPawnZeroAddress() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.requestPawn(address(0), userANftId, 1 ether, 1 days, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();
    }

    function testRequestPawnZeroAmount() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.requestPawn(address(nft), userANftId, 0, 1 days, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();
    }

    function testRequestPawnZeroDuration() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.requestPawn(address(nft), userANftId, 1 ether, 0, 1e17 /*10% interest rate annual*/ );
        vm.stopPrank();
    }

    //----removePawnRequest Tests----//

    function testRemovePawnRequest() public userAHasRequestedPawn {
        vm.startPrank(userA);
        nftPawnShop.removePawnRequest(address(nft), userANftId);
        vm.stopPrank();
        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).borrower, address(0));
        assertEq(nft.ownerOf(userANftId), userA);
    }

    function testRemovePawnRequestZeroAddress() public userAHasRequestedPawn {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.removePawnRequest(address(0), userANftId);
        vm.stopPrank();
    }

    function testRemovePawnRequestNotRequested() public {
        vm.startPrank(userA);
        vm.expectRevert();
        nftPawnShop.removePawnRequest(address(nft), userANftId);
        vm.stopPrank();
    }

    function testRemovePawnRequestAsNonOwner() public userAHasRequestedPawn {
        vm.startPrank(userB);
        vm.expectRevert(NftPawnShop.NftPawnShop__NoPawnRequestToRemove.selector);
        nftPawnShop.removePawnRequest(address(nft), userANftId);
        vm.stopPrank();
    }

    //----approvePawnRequest Tests----//

    function testApprovePawnRequest() public userAHasRequestedPawn {
        vm.startPrank(userB);
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();
        PawnAgreement memory pawnAgreement = PawnAgreement({
            borrower: userA,
            lender: userB,
            nftAddress: address(nft),
            tokenId: userANftId,
            loanAmount: 1 ether,
            loanDuration: 1 days,
            interestRate: 1e17,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            paidBackOrForeclosed: false
        });

        assertEq(nftPawnShop.getNftPawnRequest(address(nft), userANftId).borrower, address(0));
        assertEq(nftPawnShop.getNftPawnAgreement(userA).borrower, pawnAgreement.borrower);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).lender, pawnAgreement.lender);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).nftAddress, pawnAgreement.nftAddress);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).tokenId, pawnAgreement.tokenId);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).loanAmount, pawnAgreement.loanAmount);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).loanDuration, pawnAgreement.loanDuration);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).interestRate, pawnAgreement.interestRate);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).startTime, pawnAgreement.startTime);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).endTime, pawnAgreement.endTime);
        assertEq(nftPawnShop.getNftPawnAgreement(userA).paidBackOrForeclosed, pawnAgreement.paidBackOrForeclosed);
    }

    function testApprovePawnRequestWithBalanceLessThanLoanAmount() public userAHasRequestedPawn {
        address userC = makeAddr("userC");
        vm.startPrank(userC);
        vm.expectRevert();
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();
    }

    function testApprovePawnRequestWithZeroValue() public userAHasRequestedPawn {
        address userC = makeAddr("userC");
        vm.startPrank(userC);
        vm.expectRevert(abi.encodeWithSelector(NftPawnShop.NftPawnShop__InsufficientValueSent.selector, 0, 1 ether));
        nftPawnShop.approvePawnRequest(address(nft), userANftId);
        vm.stopPrank();
    }

    function testApprovePawnRequestZeroAddress() public userAHasRequestedPawn {
        vm.startPrank(userB);
        vm.expectRevert(NftPawnShop.NftPawnShop__MustNotBeZeroAddress.selector);
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(0), userANftId);
        vm.stopPrank();
    }

    function testApprovePawnRequestNotRequested() public {
        vm.startPrank(userB);
        vm.expectRevert();
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();
    }

    function testApproveOwnPawnRequest() public userAHasRequestedPawn {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__CannotApproveOwnPawnRequest.selector);
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();
    }

    //----foreclosePawnAgreement Tests----//

    function testForeclosePawnAgreement() public userARequestedAndUserBApprovedPawn {
        vm.warp(2 days);
        vm.roll(block.number + 1);
        vm.startPrank(userB);
        nftPawnShop.foreclosePawnAgreement();
        vm.stopPrank();
        assertEq(nftPawnShop.getNftPawnAgreement(userA).lender, address(0));
        assertEq(nft.ownerOf(userANftId), userB);
    }

    function testForeclosePawnAgreementNotLender() public userARequestedAndUserBApprovedPawn {
        vm.warp(2 days);
        vm.roll(block.number + 1);
        vm.startPrank(makeAddr("notLender"));
        vm.expectRevert(NftPawnShop.NftPawnShop__NoLoanToForecloseOn.selector);
        nftPawnShop.foreclosePawnAgreement();
        vm.stopPrank();
    }

    function testForeclosePawnAgreementEarly() public userARequestedAndUserBApprovedPawn {
        vm.startPrank(userB);
        vm.expectRevert(NftPawnShop.NftPawnShop__NoLoanToForecloseOn.selector);
        nftPawnShop.foreclosePawnAgreement();
        vm.stopPrank();
    }

    //----repayLoan Tests----//

    function testRepayLoanCorrect() public userARequestedAndUserBApprovedPawn {
        uint256 interestAmount = nftPawnShop.calculateInterest(1 ether, 1e17, 0, 1 days);
        uint256 repayAmount = 1 ether + interestAmount;
        vm.warp(1 days);
        vm.roll(block.number + 1);
        vm.startPrank(userA);
        nftPawnShop.repayLoan{value: repayAmount}();
        nftPawnShop.withdraw(type(uint256).max);
        vm.stopPrank();

        vm.startPrank(userB);
        nftPawnShop.withdraw(type(uint256).max);
        vm.stopPrank();
        console.log(address(nftPawnShop).balance);

        assertEq(nftPawnShop.getNftPawnAgreement(userA).lender, address(0));
        uint256 errorMargin = 0.0000000001 ether;
        assertTrue(
            ((USER_STARTING_AMOUNT - interestAmount - errorMargin) < userA.balance)
                && (userA.balance < (USER_STARTING_AMOUNT - interestAmount + errorMargin))
        );
        uint256 balanceB = userB.balance;
        uint256 feesTaken = nftPawnShop.getFeesAccumulated();
        assertTrue(
            (feesTaken - errorMargin) < (address(nftPawnShop).balance)
                && (address(nftPawnShop).balance) < (feesTaken + errorMargin)
        );
    }

    function testRepayLoanInsufficientBalance() public userARequestedAndUserBApprovedPawn {
        vm.startPrank(userA);
        nftPawnShop.withdraw(type(uint256).max);
        console.log(nftPawnShop.getBalance(userA));
        vm.expectRevert(
            abi.encodeWithSelector(NftPawnShop.NftPawnShop__InsufficientValueSent.selector, 0 ether, 1 ether)
        );
        nftPawnShop.repayLoan();
        vm.stopPrank();
    }

    function testRepayLoanAfterForeclosure() public userARequestedAndUserBApprovedPawn {
        vm.warp(2 days);
        vm.roll(block.number + 1);
        vm.startPrank(userB);
        nftPawnShop.foreclosePawnAgreement();
        vm.stopPrank();

        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__NoLoanToRepay.selector);
        nftPawnShop.repayLoan();
        vm.stopPrank();
    }

    function testRepayLoanBeforeLoan() public {
        vm.startPrank(userA);
        vm.expectRevert(NftPawnShop.NftPawnShop__NoLoanToRepay.selector);
        nftPawnShop.repayLoan();
        vm.stopPrank();
    }

    //----withdrawFees Tests----//

    function testWithdrawAllFeesAsOwner() public userAListedNft {
        // user b buys nft
        vm.startPrank(userB);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();

        uint256 feeBalanceBefore = nftPawnShop.getFeesAccumulated();
        uint256 ownerBalanceBefore = address(ownerAddress).balance;

        console.log(nftPawnShop.getFeesAccumulated());

        vm.startPrank(ownerAddress);
        nftPawnShop.withdrawFees(1 ether);
        vm.stopPrank();

        uint256 feeBalanceAfter = nftPawnShop.getFeesAccumulated();
        uint256 ownerBalanceAfter = address(ownerAddress).balance;

        assertEq(feeBalanceBefore, ownerBalanceAfter);
        assertEq(feeBalanceAfter, ownerBalanceBefore);
    }

    function testWithdrawSomeFeesAsOwner() public userAListedNft {
        // user b buys nft
        uint256 withdrawAmount = 0.01 ether;

        vm.startPrank(userB);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();

        uint256 feeBalanceBefore = nftPawnShop.getFeesAccumulated();
        uint256 ownerBalanceBefore = address(ownerAddress).balance;

        console.log(nftPawnShop.getFeesAccumulated());

        vm.startPrank(address(ownerAddress));
        nftPawnShop.withdrawFees(withdrawAmount);
        vm.stopPrank();

        uint256 feeBalanceAfter = nftPawnShop.getFeesAccumulated();
        uint256 ownerBalanceAfter = address(ownerAddress).balance;

        assertEq(feeBalanceAfter, feeBalanceBefore - withdrawAmount);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + withdrawAmount);
    }

    function testWithdrawZeroFeesAsOwner() public {
        vm.startPrank(address(ownerAddress));
        vm.expectRevert(NftPawnShop.NftPawnShop__MustBeMoreThanZero.selector);
        nftPawnShop.withdrawFees(0);
        vm.stopPrank();
    }

    function testWithdrawFeesAsNonOwner() public {
        vm.startPrank(userA);
        vm.expectRevert();
        nftPawnShop.withdrawFees(1 ether);
        vm.stopPrank();
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

    function testBuyNftSucceedsAndTakesFee() public userAListedNft {
        uint256 fee = NFT_PRICE / 100;
        vm.startPrank(userB);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();

        assertEq(nftPawnShop.getPrice(address(nft), userANftId), 0);
        assertEq(nftPawnShop.getOwner(address(nft), userANftId), address(0));
        assertEq(nftPawnShop.getBalance(userA), NFT_PRICE - fee);
        assertEq(address(nftPawnShop).balance - (nftPawnShop.getBalance(userA)), fee);
        assertEq(nft.ownerOf(userANftId), userB);
    }

    function testBuyNftAsNonListed() public {
        vm.startPrank(userB);
        vm.expectRevert();
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();
    }

    function testBuyOwnNft() public userAListedNft {
        vm.startPrank(userA);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId);
        vm.stopPrank();
        uint256 fee = NFT_PRICE / 100;
        assertEq(nftPawnShop.getBalance(userA), NFT_PRICE - fee);
    }

    function testBuyNftWithInsufficientBalance() public userAListedNft {
        vm.startPrank(userB);

        // abi.encodewithsel
        vm.expectRevert(abi.encodeWithSelector(NftPawnShop.NftPawnShop__InsufficientValueSent.selector, 0, NFT_PRICE));
        nftPawnShop.buyNft{value: 0}(address(nft), userANftId);
        vm.stopPrank();
    }

    //----deposit Tests----//

    //----withdraw Tests----//

    function testWithdrawNormal() public userAHasBalance {
        vm.startPrank(userA);
        nftPawnShop.withdraw(9.9 ether);
        vm.stopPrank();
        assertEq(nftPawnShop.getBalance(userA), 0);
        assertEq(address(nftPawnShop).balance, 0.1 ether);
        assertEq(address(userA).balance, USER_STARTING_AMOUNT + 9.9 ether);
    }

    function testWithdrawMoreThanBalance() public userAHasBalance {
        vm.startPrank(userA);
        nftPawnShop.withdraw(2 * USER_STARTING_AMOUNT);
        vm.stopPrank();
        assertEq(nftPawnShop.getBalance(userA), 0);
        assertEq(address(nftPawnShop).balance, 0.1 ether);
        assertEq(address(userA).balance, USER_STARTING_AMOUNT + 9.9 ether);
    }

    function testWithdrawZero() public userAHasBalance {
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

    //----getOwnerOfContract Tests----//

    function testGetOwnerOfContract() public {
        assertEq(nftPawnShop.getOwnerOfContract(), ownerAddress);
    }

    //----calculateInterest tests----//

    function testCalculateInterest1() public {
        uint256 interest = nftPawnShop.calculateInterest(10 ether, 1e18, 0, 1 days);
        console.log(interest);
        uint256 expectedInterest = 273972602739726;
        assertEq(interest, expectedInterest);
    }

    function testCalculateInterest2() public {
        uint256 interest = nftPawnShop.calculateInterest(10 ether, 1e18, 0, 365 days);
        console.log(interest);
        uint256 expectedInterest = 0.1 ether;
        assertEq(interest, expectedInterest);
    }

    //----One off tests----//

    function testOneBigTestListing() public userAListedNft {
        vm.startPrank(userA);
        nftPawnShop.removeListing(address(nft), userANftId);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.listNft(address(nft), userANftId, NFT_PRICE);
        vm.stopPrank();

        //user b buys user a nft
        vm.startPrank(userB);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userANftId); // userA balance = 90 + 10 - 0.1 = 99.9, userB balance = 200 - 10
        vm.stopPrank();

        //user b lists nft
        vm.startPrank(userB);
        nft.approve(address(nftPawnShop), userBNftId);
        nftPawnShop.listNft(address(nft), userBNftId, NFT_PRICE);
        nftPawnShop.updateListingPrice(address(nft), userBNftId, NFT_PRICE * 2);
        vm.stopPrank();

        //user a buys user b nft
        vm.startPrank(userA);
        nftPawnShop.buyNft{value: NFT_PRICE * 2}(address(nft), userBNftId); // userA balance = 99.9 - 20 = 79.9, userB balance = 200 + 20
        vm.stopPrank();

        //user b withdraws all funds
        vm.startPrank(userB);
        nftPawnShop.withdraw(100 ether);
        vm.stopPrank();

        vm.startPrank(userA);
        nftPawnShop.withdraw(100 ether);
        vm.stopPrank();

        assertEq(nftPawnShop.getBalance(userA), 0);
        assertEq(nftPawnShop.getBalance(userB), 0);
        assertEq(userA.balance, 89.9 ether);
        assertEq(nft.ownerOf(userANftId), userB);
        assertEq(nft.ownerOf(userBNftId), userA);
    }
    /**
     * @notice Sequence of funciton calls
     * @dev
     * 1. userB lists nft
     * 2. userA requests pawn
     * 3. userB withdraws 1 eth
     * 4. userB approves pawn
     * 5. userA buys nft from userB
     * 6. userB forecloses pawn agreement with userA
     * 7. Check that the nfts have swapped owners
     */

    function testOneBigTestPawn() public {
        vm.startPrank(userB);
        nft.approve(address(nftPawnShop), userBNftId);
        nftPawnShop.listNft(address(nft), userBNftId, NFT_PRICE);
        vm.stopPrank();

        vm.startPrank(userA);
        nft.approve(address(nftPawnShop), userANftId);
        nftPawnShop.requestPawn(address(nft), userANftId, 1 ether, 1 days, 1e17);
        vm.stopPrank();

        vm.startPrank(userB);
        nftPawnShop.withdraw(1 ether);
        nftPawnShop.approvePawnRequest{value: 1 ether}(address(nft), userANftId);
        vm.stopPrank();

        vm.startPrank(userA);
        nftPawnShop.buyNft{value: NFT_PRICE}(address(nft), userBNftId);
        vm.stopPrank();

        vm.roll(block.number + 1);
        vm.warp(2 days);

        vm.startPrank(userB);
        nftPawnShop.foreclosePawnAgreement();
        vm.stopPrank();

        assertEq(nft.ownerOf(userANftId), userB);
        assertEq(nft.ownerOf(userBNftId), userA);
        assertEq(nftPawnShop.getBalance(userA), 1 ether);
        assertEq(nftPawnShop.getBalance(userB), 9.9 ether);
        assertEq(userB.balance, USER_STARTING_AMOUNT - 1 ether);
    }
    //9900000000000000000
    //9000000000000000000
}
