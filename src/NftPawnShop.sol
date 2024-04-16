// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// @note use reentrancy guard?

contract NftPawnShop is Ownable {
    // Type Declarations
    ////////////////////

    // Structs
    ////////////////////
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

    // State Variables
    ////////////////////
    uint256 private constant FEE_DIVISOR = 100;
    uint256 private constant INTEREST_PRECISION = 100e18;

    mapping(address nftAddress => mapping(uint256 tokenId => uint256 price)) private s_nftPrice;
    mapping(address nftAddress => mapping(uint256 tokenId => address owner)) private s_nftListingOwner;

    // maps token to pawn request which contains the owner
    mapping(address nftAddress => mapping(uint256 tokenId => PawnRequest)) private s_nftPawnRequests;
    mapping(address borrower => PawnAgreement) private s_pawnAgreements;

    mapping(address user => uint256 balance) private s_userBalances;
    uint256 private s_feesAccumulated;

    // Events
    ////////////////////
    event NftListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NftDelisted(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event NftSold(address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price);

    event PawnRequested(
        address indexed borrower,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 loanAmount,
        uint256 loanDuration,
        uint256 interestRate
    );
    event PawnRequestRemoved(address indexed borrower, address indexed nftAddress, uint256 indexed tokenId);
    event PawnRequestApproved(
        address borrower,
        address indexed lender,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 loanAmount,
        uint256 loanDuration,
        uint256 interestRate
    );
    event PawnAgreementRemoved(
        address borrower, address indexed lender, address indexed nftAddress, uint256 indexed tokenId
    );

    // Errors
    ////////////////////
    error NftPawnShop__MustNotBeZeroAddress();
    error NftPawnShop__MustBeMoreThanZero();
    error NftPawnShop__MustBeOwner();
    error NftPawnShop__NftAlreadyListed(address nftAddress, uint256 tokenId);
    error NftPawnShop__NftNotListed(address nftAddress, uint256 tokenId);
    error NftPawnShop__InsufficientBalance(uint256 amount, uint256 balance);
    error NftPawnShop__NoLoanToRepay();
    error NftPawnShop__NoLoanToForecloseOn();
    error NftPawnShop__NoPawnRequestToRemove();
    error NftPawnShop__CannotApproveOwnPawnRequest();
    error NftPawnShop__InsufficientValueSent(uint256 valueSent, uint256 price);
    // Modifiers
    ////////////////////

    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert NftPawnShop__MustNotBeZeroAddress();
        }
        _;
    }

    modifier notZero(uint256 _amount) {
        if (_amount == 0) {
            revert NftPawnShop__MustBeMoreThanZero();
        }
        _;
    }

    modifier onlyOwnerOfNft(address nftAddress, uint256 tokenId) {
        IERC721 nft = IERC721(nftAddress);
        if (s_nftListingOwner[nftAddress][tokenId] != msg.sender) {
            revert NftPawnShop__MustBeOwner();
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        if (s_nftPrice[nftAddress][tokenId] == 0) {
            revert NftPawnShop__NftNotListed(nftAddress, tokenId);
        }
        _;
    }

    // Functions
    ////////////////////

    //----Constructor----//

    constructor() Ownable(msg.sender) {}

    //----External Functions----//

    /**
     * @dev ERC721 token receiver function
     * @dev This function is called when an NFT is sent to the contract with safe transfer.
     * @dev It is required to receive NFTs.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    /**
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param loanAmount Amount of the loan
     * @param loanDuration Duration of the loan
     * @param interestRate Interest rate of the loan in percentage. 1e18 is 100%. 1e17 is 10%. and so on.
     * @dev The potential borrower requests a loan of loanAmount eth for loanDuration days with an interest rate of interestRate and
     * deposits the nft as collateral. The nft is transferred to the contract.
     */
    function requestPawn(
        address nftAddress,
        uint256 tokenId,
        uint256 loanAmount,
        uint256 loanDuration,
        uint256 interestRate
    ) external notZeroAddress(nftAddress) notZero(loanAmount) notZero(loanDuration) {
        PawnRequest memory pawnRequest = PawnRequest({
            borrower: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            loanAmount: loanAmount,
            loanDuration: loanDuration,
            interestRate: interestRate
        });

        s_nftPawnRequests[nftAddress][tokenId] = pawnRequest;
        emit PawnRequested(msg.sender, nftAddress, tokenId, loanAmount, loanDuration, interestRate);

        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @dev The borrower cancels the pawn request and the nft is transferred back to the borrower.
     */
    function removePawnRequest(address nftAddress, uint256 tokenId) external notZeroAddress(nftAddress) {
        PawnRequest memory pawnRequest = s_nftPawnRequests[nftAddress][tokenId];
        if (pawnRequest.borrower != msg.sender) {
            revert NftPawnShop__NoPawnRequestToRemove();
        }
        _removePawnRequest(nftAddress, tokenId);
        emit PawnRequestRemoved(msg.sender, nftAddress, tokenId);

        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @dev The lender approves the pawn request and the eth loan amount is transferred to the borrowers balace within the contract.
     * The nft is locked up in the contract and
     * can only be returned to the initial owner if the loan is repaid.
     */
    function approvePawnRequest(address nftAddress, uint256 tokenId) external payable notZeroAddress(nftAddress) {
        PawnRequest memory pawnRequest = s_nftPawnRequests[nftAddress][tokenId];
        if (pawnRequest.borrower == address(0)) {
            revert NftPawnShop__NftNotListed(nftAddress, tokenId);
        }
        if (pawnRequest.borrower == msg.sender) {
            revert NftPawnShop__CannotApproveOwnPawnRequest();
        }
        if (msg.value < pawnRequest.loanAmount) {
            revert NftPawnShop__InsufficientValueSent(msg.value, pawnRequest.loanAmount);
        }

        emit PawnRequestApproved(
            pawnRequest.borrower,
            msg.sender,
            nftAddress,
            tokenId,
            pawnRequest.loanAmount,
            pawnRequest.loanDuration,
            pawnRequest.interestRate
        );

        PawnAgreement memory pawnAgreement = PawnAgreement({
            borrower: pawnRequest.borrower,
            lender: msg.sender,
            nftAddress: pawnRequest.nftAddress,
            tokenId: pawnRequest.tokenId,
            loanAmount: pawnRequest.loanAmount,
            loanDuration: pawnRequest.loanDuration,
            interestRate: pawnRequest.interestRate,
            startTime: block.timestamp,
            endTime: block.timestamp + pawnRequest.loanDuration,
            paidBackOrForeclosed: false
        });

        // delete pawn request
        s_nftPawnRequests[nftAddress][tokenId] = PawnRequest({
            borrower: address(0),
            nftAddress: address(0),
            tokenId: 0,
            loanAmount: 0,
            loanDuration: 0,
            interestRate: 0
        });

        s_pawnAgreements[pawnRequest.borrower] = pawnAgreement;
        s_pawnAgreements[msg.sender] = pawnAgreement;

        s_nftPawnRequests[nftAddress][tokenId] = PawnRequest({
            borrower: address(0),
            nftAddress: address(0),
            tokenId: 0,
            loanAmount: 0,
            loanDuration: 0,
            interestRate: 0
        });

        s_userBalances[pawnRequest.borrower] += msg.value;
    }

    /**
     *
     * @dev Checks if the loan is due and if it is and the loan hasnt been paid back in full, the nft is transferred to the lender.
     */
    function foreclosePawnAgreement() external {
        PawnAgreement memory pawnAgreement = s_pawnAgreements[msg.sender];
        if (pawnAgreement.lender != msg.sender) {
            revert NftPawnShop__NoLoanToForecloseOn();
        }
        if (block.timestamp > pawnAgreement.endTime && !pawnAgreement.paidBackOrForeclosed) {
            _removePawnAgreement(pawnAgreement.lender, pawnAgreement.borrower);
            emit PawnAgreementRemoved(
                pawnAgreement.borrower, pawnAgreement.lender, pawnAgreement.nftAddress, pawnAgreement.tokenId
            );

            IERC721 nft = IERC721(pawnAgreement.nftAddress);
            nft.safeTransferFrom(address(this), msg.sender, pawnAgreement.tokenId);
        } else {
            revert NftPawnShop__NoLoanToForecloseOn();
        }
    }

    /**
     *
     * @dev The borrower repays the loan and the nft is transferred back to the borrower.
     * If the loan is overdue but the lender hasnt called foreclosure yet, the borrower can repay the loan with the interest being
     * calculated from start time to now instead of start time to end time and they get the nft back. e.i if the agreed period was
     * 1 day and its paid back in 2 days, the interest paid will be calculated from 2 days instead of 1 day.
     */
    function repayLoan() external payable {
        PawnAgreement memory pawnAgreement = s_pawnAgreements[msg.sender];
        if (pawnAgreement.lender == address(0) || pawnAgreement.borrower != msg.sender) {
            revert NftPawnShop__NoLoanToRepay();
        }

        uint256 interestAmount = calculateInterest(
            pawnAgreement.loanAmount, pawnAgreement.interestRate, pawnAgreement.startTime, block.timestamp
        );
        uint256 amountToRepay = pawnAgreement.loanAmount + interestAmount;
        if (msg.value < amountToRepay) {
            revert NftPawnShop__InsufficientValueSent(msg.value, amountToRepay);
        }

        _removePawnAgreement(pawnAgreement.lender, pawnAgreement.borrower);
        emit PawnAgreementRemoved(
            pawnAgreement.borrower, pawnAgreement.lender, pawnAgreement.nftAddress, pawnAgreement.tokenId
        );

        uint256 fee = amountToRepay / FEE_DIVISOR;

        s_userBalances[pawnAgreement.lender] += amountToRepay - fee;

        s_feesAccumulated += fee;

        address nftAddress = pawnAgreement.nftAddress;
        uint256 tokenId = pawnAgreement.tokenId;
        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    //----Public Functions----//

    /*
        * @dev Withdraw accumulated fees as owner
        * @param amount Amount of fees to withdraw
        * @dev The amount of fees to withdraw is checked against the accumulated fees.
        * If the amount is greater than the accumulated fees, the entire accumulated fees are withdrawn.
        * If the amount is less than or equal to the accumulated fees, the amount is withdrawn.
        */
    function withdrawFees(uint256 amount) public onlyOwner notZero(amount) {
        if (amount > getFeesAccumulated()) {
            amount = getFeesAccumulated();
        }
        s_feesAccumulated -= amount;
        payable(owner()).transfer(amount);
    }

    /**
     * @dev List an NFT for sale
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param price Price of the NFT
     * @dev The mapping of the NFT address and the token ID is set to the price of the listed nft.
     * then an event is emitted to notify the listing of the NFT and the NFT is sent to the contract.
     *
     */
    function listNft(address nftAddress, uint256 tokenId, uint256 price)
        external
        notZero(price)
        notZeroAddress(nftAddress)
    {
        if (s_nftPrice[nftAddress][tokenId] != 0) {
            // @note Can only hit when contract itself calls this function with an already listed nft.
            revert NftPawnShop__NftAlreadyListed(nftAddress, tokenId);
        }
        _setListing(nftAddress, tokenId, price);
        s_nftListingOwner[nftAddress][tokenId] = msg.sender;
        emit NftListed(msg.sender, nftAddress, tokenId, price);
        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @dev Remove an NFT from sale
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @dev The mapping of the NFT address and the token ID is set to 0. This is the equivalent of removing the listing.
     */
    function removeListing(address nftAddress, uint256 tokenId)
        public
        notZeroAddress(nftAddress)
        onlyOwnerOfNft(nftAddress, tokenId)
        isListed(nftAddress, tokenId)
    {
        _removeListing(nftAddress, tokenId);
        emit NftDelisted(msg.sender, nftAddress, tokenId);
        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev Update the price of a listed NFT
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param price New price of the NFT
     * @dev The mapping of the NFT address and the token ID is set to the new price of the listed nft.
     */
    function updateListingPrice(address nftAddress, uint256 tokenId, uint256 price)
        public
        notZero(price)
        notZeroAddress(nftAddress)
        onlyOwnerOfNft(nftAddress, tokenId)
        isListed(nftAddress, tokenId)
    {
        _setListing(nftAddress, tokenId, price);
        emit NftListed(msg.sender, nftAddress, tokenId, price);
    }

    /**
     * @dev Buy an NFT
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @dev The price of the NFT is checked against the amount of ETH sent. If the amounts do not match,
     * the transaction is reverted.
     * If the amounts match, the NFT is transferred to the buyer and the seller is paid.
     * The price of the NFT is set to 0 and the user's balance is updated.
     * the protocol takes a 1% fee from the seller.
     */
    // @note reentrancy?
    function buyNft(address nftAddress, uint256 tokenId) public payable isListed(nftAddress, tokenId) {
        uint256 price = s_nftPrice[nftAddress][tokenId];
        if (msg.value < price) {
            revert NftPawnShop__InsufficientValueSent(msg.value, price);
        }

        address seller = s_nftListingOwner[nftAddress][tokenId];
        uint256 fee = price / FEE_DIVISOR;
        uint256 payout = price - fee;

        s_feesAccumulated += fee;

        s_userBalances[seller] += payout;
        _removeListing(nftAddress, tokenId);
        emit NftSold(msg.sender, nftAddress, tokenId, price);

        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev Withdraw ETH from the contract
     * @param amount Amount of ETH to withdraw
     * @dev The amount of ETH to withdraw is checked against the user's balance.
     * If the amount is greater than the user's balance, the user's entire balance is withdrawn.
     * If the amount is less than or equal to the user's balance, the amount is withdrawn.
     */
    function withdraw(uint256 amount) public notZero(amount) {
        uint256 userBalance = s_userBalances[msg.sender];
        if (userBalance < amount) {
            amount = userBalance;
        }
        s_userBalances[msg.sender] -= amount;

        payable(msg.sender).transfer(amount);
    }

    function getUserBalance(address user) public view returns (uint256) {
        return s_userBalances[user];
    }

    function getNftPawnRequest(address nftAddress, uint256 tokenId) public view returns (PawnRequest memory) {
        return s_nftPawnRequests[nftAddress][tokenId];
    }

    function getNftPawnAgreement(address user) public view returns (PawnAgreement memory) {
        return s_pawnAgreements[user];
    }

    /**
     * @dev Get the price of a listed NFT
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @return price Price of the NFT
     */
    function getPrice(address nftAddress, uint256 tokenId) public view returns (uint256) {
        return s_nftPrice[nftAddress][tokenId];
    }

    /**
     * @dev Get the owner of a listed NFT
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @return owner Address of the owner of the NFT. Returns zero if the NFT is not listed.
     */
    function getOwner(address nftAddress, uint256 tokenId) public view returns (address) {
        return s_nftListingOwner[nftAddress][tokenId];
    }

    function getBalance(address user) public view returns (uint256) {
        return s_userBalances[user];
    }

    /**
     * @dev Get the amount of fees accumulated by the protocol
     * @return feesAccumulated Amount of fees accumulated
     */
    // @note maybe make this onlyOwner?
    function getFeesAccumulated() public view returns (uint256) {
        return s_feesAccumulated;
    }

    /**
     * @dev Get the owner of the contract
     * @return owner Address of the owner of the contract
     */
    // @note maybe redundant?
    function getOwnerOfContract() public view returns (address) {
        return owner();
    }

    function calculateInterest(uint256 loanAmount, uint256 interestRate, uint256 startTime, uint256 endTime)
        public
        view
        returns (uint256)
    {
        return _calculateInterest(loanAmount, interestRate, startTime, endTime);
    }

    /**
     * @dev Get the owner of a listed NFT
     * @return nftAddresses Addresses of the NFT contracts
     * @return tokenIds IDs of the NFTs
     * @dev The indexes match, so the first address in the array is the nftAddress of nft number 0
     * and the first token ID in the array is the token ID of nft number 0. And so on.
     */
    function getAllListedNfts() public view returns (address[] memory nftAddresses, uint256[] memory tokenIds) {}

    //----Internal Functions----//

    function _removePawnRequest(address nftAddress, uint256 tokenId) internal {
        s_nftPawnRequests[nftAddress][tokenId] = PawnRequest({
            borrower: address(0),
            nftAddress: address(0),
            tokenId: 0,
            loanAmount: 0,
            loanDuration: 0,
            interestRate: 0
        });
    }

    // @note maybe rounding error?
    function _calculateInterest(uint256 loanAmount, uint256 interestRate, uint256 startTime, uint256 endTime)
        internal
        view
        returns (uint256)
    {
        // Calculate elapsed time in seconds
        uint256 elapsedTime = endTime - startTime;
        // Calculate interest accrued
        uint256 interestAmount = (loanAmount * interestRate * elapsedTime) / (365 days * INTEREST_PRECISION); // Assuming a 365-day year

        return interestAmount;
    }

    /**
     * @dev Set the price of a listed NFT
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param price Price of the NFT
     * @dev The mapping of the NFT address and the token ID is set to the price of the listed nft.
     */
    function _setListing(address nftAddress, uint256 tokenId, uint256 price) internal {
        s_nftPrice[nftAddress][tokenId] = price;
    }

    function _removeListing(address nftAddress, uint256 tokenId) internal {
        _setListing(nftAddress, tokenId, 0);
        s_nftListingOwner[nftAddress][tokenId] = address(0);
    }

    function _removePawnAgreement(address borrower, address lender) internal {
        s_pawnAgreements[borrower] = PawnAgreement({
            borrower: address(0),
            lender: address(0),
            nftAddress: address(0),
            tokenId: 0,
            loanAmount: 0,
            loanDuration: 0,
            interestRate: 0,
            startTime: 0,
            endTime: 0,
            paidBackOrForeclosed: false
        });
        s_pawnAgreements[lender] = PawnAgreement({
            borrower: address(0),
            lender: address(0),
            nftAddress: address(0),
            tokenId: 0,
            loanAmount: 0,
            loanDuration: 0,
            interestRate: 0,
            startTime: 0,
            endTime: 0,
            paidBackOrForeclosed: false
        });
    }
}
