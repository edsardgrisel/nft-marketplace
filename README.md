# Pawn Shop NFT Marketplace

Pawn Shop NFT Marketpalce is a decentralized application (dApp) that allows users to buy, sell, and pawn non-fungible tokens (NFTs) on the Ethereum blockchain.
The project is built using the following technologies:
- Solidity
- Foundry

## Table of Contents

1. [Installation](#installation)
2. [Usage](#usage)
3. [Features](#features)

## Installation


## Usage
### Sepolia:

deploy: `make deploy ARGS="--network sepolia"`

verify(if verification fails with deploy): `forge verify-contract --chain sepolia {contract address} NftPawnShop --watch`

To deploy marketplace and mint some nfts: `make deploy && make deployNft`

### Local:

mint nfts: `make mintNft`

## Features

### Depositing and withdrawing
- Users deposit eth in order to buy nfts or lend out eth
- Users can withdraw eth from their account
- Owner can withdraw fees from the contract

### Buying and Selling
- Users can buy and sell NFTs on the marketplace.
- Sellers can list their NFTs for sale for a given ETH amount.
- Buyers can purchase NFTs from other users for a given ETH amount.
- The marketplace takes a 1% commission from the sale of NFTs. E.g an nft listed for 100 eth will be bought for 100 eth by the buyer and the seller will receive 99 eth.

### Pawning
- Users can pawn their NFTs.
- Borrowers can list their NFT as collateral in order to borrow a given ETH amount at a certain interest rate for a certain duration.
- Lenders can take the NFT as collateral and lend out the given ETH amount.
- The borrower must then payback the loan amount + interest in the given amount of time in order to claim the NFT back.
- If the borrower fails to repay the loan amount + interest in the given amount of time, the lender will claim the NFT as collateral (foreclosure).
- Note: users can only be part of one pawn at a time as either a borrower or lender. If a user is already a borrower in a pawn,
they must pay back the loan amount + interest in order to pawn another NFT or lend out. If a user is already a lender in a pawn,
the loan must either be paid back or the pawn must be foreclosed in order to lend out another loan or to pawn an NFT. A user can be part of a pawn and also buy and sell NFTs on the marketplace.




## Potential Improvements
- fix interest math?
- Helper methods in the test file to calcualte whether 2 structs are equal to reduce code duplication