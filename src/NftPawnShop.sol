// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// @note use reentrancy guard?

contract NftPawnShop is Ownable {
    // Type Declarations
    ////////////////////

    // State Variables
    ////////////////////
    mapping(address nftAddress => mapping(uint256 tokenId => uint256 price)) private s_nftPrice;
    mapping(address nftAddress => mapping(uint256 tokenId => address owner)) private s_nftOwner;
    mapping(address user => uint256 balance) private s_userBalances;

    // Events
    ////////////////////
    event NftListed(address nftAddress, uint256 tokenId, uint256 price);
    event NftDelisted(address indexed nftAddress, uint256 indexed tokenId);
    event NftListingUpdated(address nftAddress, uint256 tokenId, uint256 price);
    event NftSold(address nftAddress, uint256 tokenId, address buyer, address seller, uint256 price);

    // Errors
    ////////////////////
    error NftPawnShop__MustNotBeZeroAddress();
    error NftPawnShop__MustBeMoreThanZero();
    error NftPawnShop__MustBeOwner();
    error NftPawnShop__NftAlreadyListed(address nftAddress, uint256 tokenId);
    error NftPawnShop__NftNotListed(address nftAddress, uint256 tokenId);
    error NftPawnShop__InsufficientBalance(uint256 price, uint256 balance);

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
        if (s_nftOwner[nftAddress][tokenId] != msg.sender) {
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

    //----Public Functions----//

    /**
     * @dev List an NFT for sale
     * @param nftAddress Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param price Price of the NFT
     * @dev The mapping of the NFT address and the token ID is set to the price of the listed nft.
     * then an event is emitted to notify the listing of the NFT and the NFT is sent to the contract.
     *
     */
    // @note onlyOwnerOfNft modifier might be redundant as safeTransfer already checks this for both remove
    // and list functions?
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
        s_nftOwner[nftAddress][tokenId] = msg.sender;
        emit NftListed(nftAddress, tokenId, price);
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
        emit NftDelisted(nftAddress, tokenId);
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
        emit NftListingUpdated(nftAddress, tokenId, price);
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
    function buyNft(address nftAddress, uint256 tokenId) public isListed(nftAddress, tokenId) {
        uint256 price = s_nftPrice[nftAddress][tokenId];
        uint256 userBalance = s_userBalances[msg.sender];
        if (userBalance < price) {
            revert NftPawnShop__InsufficientBalance(price, userBalance);
        }

        address seller = s_nftOwner[nftAddress][tokenId];
        uint256 fee = price / 100;
        uint256 payout = price - fee;
        s_userBalances[msg.sender] -= price;

        s_userBalances[seller] += payout;
        _removeListing(nftAddress, tokenId);
        emit NftSold(nftAddress, tokenId, msg.sender, seller, price);

        IERC721 nft = IERC721(nftAddress);
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev Deposit ETH into the contract
     * @dev The amount of ETH sent is added to the user's balance.
     */
    function deposit() public payable {
        if (msg.value <= 0) {
            revert NftPawnShop__MustBeMoreThanZero();
        }
        s_userBalances[msg.sender] += msg.value;
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
        return s_nftOwner[nftAddress][tokenId];
    }

    function getBalance(address user) public view returns (uint256) {
        return s_userBalances[user];
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
        s_nftOwner[nftAddress][tokenId] = address(0);
    }
}
