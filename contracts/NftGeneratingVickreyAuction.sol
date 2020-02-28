pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";

// Based on - https://programtheblockchain.com/posts/2018/04/03/writing-a-vickrey-auction-contract/

contract NftGeneratingVickreyAuction {

    /////////////////////
    // Auction Details //
    /////////////////////

    IERC20 public paymentToken;
    IERC721 public nftMinter;

    uint256 public reservePrice;
    uint256 public endOfBidding;
    uint256 public endOfRevealing;

    uint256 public totalItemsForSale = 0;
    bool public auctionResulted = false;
    bool public auctionClosed = false;

    address public auctionCreator;

    //////////////////////////
    // Participants Details //
    //////////////////////////

    struct Bidder {
        address bidder;
        uint256 balance;
        uint256 hashedBid;
        uint256 revealedAmount;
        bool revealed;
        bool reconciled;
    }

    mapping(address => Bidder) participants;

    /////////////////
    // The Auction //
    /////////////////

    // TODO probs best created through a AuctionFactory contract so can easily watch and subgraph it

    constructor(
        IERC20 _paymentToken, // DAI / WETH etc
        IERC721 _nftMinter, // NFT receipt
        uint256 _reservePrice, // Auction base price e.g. $30
        uint256 _totalItemsForSale, // Max allowed items in the auction
        uint256 _biddingPeriod, // How long is the action going to last for
        uint256 _revealingPeriod // How long in seconds after auction close is the bidder allowed to reveal there bid for
    ) public {
        paymentToken = _paymentToken;
        nftMinter = _nftMinter;

        reservePrice = _reservePrice;

        // Auction closes from now + total auction time
        endOfBidding = now + _biddingPeriod;

        // End of auction + end of reveal = time span you MUST reveal your bid in
        endOfRevealing = endOfBidding + _revealingPeriod;

        // max number of items for sale for this auction
        totalItemsForSale = _totalItemsForSale;

        auctionCreator = msg.sender;

        // the seller can't bid, but this simplifies withdrawal logic
        revealed[auctionCreator] = true;
    }

    // hash = hash(amount + salt)
    // _biddingAmount = possibly over committed bidding amount
    function placeBid(bytes32 _hashedAmount, uint256 _biddingAmount) public returns (bool) {
        require(now < endOfBidding, "Auction bidding time period has closed");
        require(msg.sender != auctionCreator, "Creator cannot bid on their own items");
        require(_biddingAmount >= reservePrice, "Bid does not meet reserve price");

        Bidder storage participants = participants[msg.sender];
        participants.bidder = msg.sender;

        // can the user make another higher bid - if so handle this case?
        require(participants.balance == 0, "User already made a bid");

        participants.hashedBid = _hashedAmount;
        participants.balance = _biddingAmount;

        // Take ownership of the payment token
        require(IERC20(_paymentToken).transferFrom(msg.sender, address(this), _biddingAmount), "Unable to escrow funds for bid");

        return true;
    }

    function revealBid(uint256 _proposedRevealAmount, uint256 _salt) public returns (bool) {
        require(now >= endOfBidding && now < endOfRevealing, "Reveal period has already closed");

        Bidder storage participants = participants[msg.sender];

        // Ensure users results valid
        require(keccak256(_proposedRevealAmount, _salt) == participants.hashedBid, "Unable to find sealed bid");

        // Ensure not already revealed
        require(participants.revealed, "User already revealed bid");
        participants.revealed = true;

        // insufficient funds to cover bid amount, so ignore it
        require(_proposedRevealAmount >= participants.balance, "Insufficient funds to cover bid");

        // Record the actual revealed amount
        participants.revealedAmount = _proposedRevealAmount;

        // Work out the over commitment
        uint256 overCommittedAmount = participants.balance - _proposedRevealAmount;

        // Ensure balance is set to revealed amount
        participants.balance = _proposedRevealAmount;

        // Send back the over committed amount
        require(IERC20(_paymentToken).transferFrom(address(this), msg.sender, overCommittedAmount), "Unable to send back over committed funds");

        // TODO handle penalisation of cheats ... ?

        return true;
    }

    // Allowing claim NFT not sending?
    //    function claim() public {
    //        require(now >= endOfRevealing);
    //
    //        uint256 t = token.balanceOf(this);
    //        require(token.transfer(highBidder, t));
    //    }

    // TODO handle burn condition when someone does not reveal in time?¬

    function resultAuction() public {
        require(now > endOfRevealing, "Reveal period has not closed yet");
        require(auctionCreator == msg.sender, "Cannot only be resulted by the auction creator");
        require(!auctionResulted, "Already resulted");

        // Ensure auction is resulted
        auctionResulted = true;

        // TODO How to handle when not enough bids made?

        for (uint i = 0; i < participants.length; i++) {
            Bidder storage bidder = participants[i];

            // Place revealed list into a order list based on amount committed

        }

        // send balance to auction creator
        // all others can be penalised
    }

    function closeAuction() public {
        require(auctionCreator == msg.sender, "Cannot only be resulted by the auction creator");
        require(auctionResulted, "Auction not resulted yet");
        require(!auctionClosed, "Auction already closed");

        // Ensure auction is now closed
        auctionClosed = true;

        // generates X number of NFTS for those who won
    }

    // ATM you can only withdraw once you have revealed you bid
    // TODO revert when trying to withdraw post reveal close and after its resulted

    function withdraw() public {
        require(now > endOfRevealing, "Reveal period has not closed yet");
        require(revealed[msg.sender], "User has not revealed amount yet");
        require(!auctionResulted, "Auction has already been resulted");

        uint256 amount = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;

        // TODO

        require(IERC20(_paymentToken).transferFrom(address(this), msg.sender, amount), "Unable to sends funds back");
    }
}
