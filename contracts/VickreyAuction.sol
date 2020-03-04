pragma solidity ^0.5.12;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract VickreyAuction {
    using SafeMath for uint256;

    /////////////////////
    // Auction Details //
    /////////////////////

    IERC20 public paymentToken;
    IERC721 public nftMinter;

    // Auction Config
    uint256 public reservePrice;
    uint256 public endOfBidding;
    uint256 public endOfRevealing;
    uint256 public totalItemsForSale = 0;

    bool public auctionResulted = false;
    bool public auctionClosed = false;

    address public owner;

    //////////////////////////
    // Participants Details //
    //////////////////////////

    struct Bidder {
        address bidder;
        uint256 tokenCommitment;
        bytes32 sealedBid;
        uint256 revealedBid;
        bool hasRevealed;
    }

    mapping(address => Bidder) participants;

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyOwner(){
        require(msg.sender == owner, "Only owner operation");
        _;
    }

    modifier onlyWhenBiddingOpen(){
        require(now < endOfBidding, "Auction bidding time period has closed");
        _;
    }

    modifier onlyWhenRevealingOpen(){
        require(now > endOfBidding && now < endOfBidding, "Auction reveal stage not started yet");
        _;
    }

    modifier onlyWhenReservePriceReached(uint256 _biddingAmount){
        require(_biddingAmount >= reservePrice, "Bid does not met reserve price");
        _;
    }

    /////////////////
    // The Auction //
    /////////////////

    constructor(
        IERC20 _paymentToken, // DAI / WETH etc
        IERC721 _nftMinter, // NFT receipt
        uint256 _reservePrice, // Auction base price e.g. $30
        uint256 _totalItemsForSale, // Max allowed items in the auction
        uint256 _biddingPeriod, // How long is the action going to last for
        uint256 _revealingPeriod, // How long in seconds after auction close is the bidder allowed to reveal there bid for
        address _owner
    ) public {
        require(_owner != address(0), "Owner must exist");

        // How to take payment e.g. DAI, WETH etc
        paymentToken = _paymentToken;

        // How to issue NFT receipt
        nftMinter = _nftMinter;

        // Auction base price e.g. $30
        reservePrice = _reservePrice;

        // Auction closes from now + total auction time
        endOfBidding = now + _biddingPeriod;

        // End of auction + end of reveal = time span you MUST reveal your bid in
        endOfRevealing = endOfBidding + _revealingPeriod;

        // max number of items for sale for this auction
        totalItemsForSale = _totalItemsForSale;

        // Who has admin access
        owner = _owner;

        // the seller can't bid, but this simplifies withdrawal logic
        Bidder storage bidder = participants[owner];
        bidder.bidder = owner;
        bidder.hasRevealed = true;
    }

    /**
     * Place a bid
     * @dev A user can place as many bids as they want, if they have previously placed a bid the previous bid amount if returned and a new one is set
     * @param _sealedBid the hash(amount + salt) which is needed to be reveal the bid later in the process
     * @param _tokenOverCommitment the over committed that is being offered
     */
    function placeBid(bytes32 _sealedBid, uint256 _tokenOverCommitment)
    onlyWhenBiddingOpen
    onlyWhenReservePriceReached(_tokenOverCommitment)
    public
    returns (bool) {
        require(msg.sender != owner, "Creator cannot bid on their own items");

        Bidder storage bidder = participants[msg.sender];
        bidder.bidder = msg.sender;
        // TODO can we ditch this prop

        // Return the funds already committed if they have some
        if (bidder.tokenCommitment > 0) {
            require(IERC20(paymentToken).transferFrom(address(this), msg.sender, bidder.tokenCommitment), "Unable to return existing token commitment");
        }

        // Update the props
        bidder.sealedBid = _sealedBid;
        bidder.tokenCommitment = _tokenOverCommitment;

        // Take ownership of the payment token (escrow into this contract)
        require(IERC20(paymentToken).transferFrom(msg.sender, address(this), _tokenOverCommitment), "Unable to escrow funds for bid");

        return true;
    }

    /**
     * Withdraw your bid
     * @dev A user can withdraw a offer ONLY when the bidding stage is open
     * @dev Once withdraw all token commitment is returned and biding data is reset
     */
    function withdraw()
    onlyWhenBiddingOpen
    public
    returns (bool) {
        Bidder storage bidder = participants[msg.sender];

        uint256 tokenCommitment = bidder.tokenCommitment;
        require(tokenCommitment > 0, "No open bid to withdraw");

        bidder.tokenCommitment = 0;
        bidder.sealedBid = 0;

        require(IERC20(paymentToken).transferFrom(address(this), msg.sender, tokenCommitment), "Unable to withdraw token commitment");

        return true;
    }

    /**
     * Reveal your bid
     * @dev A user can place as many bids as they want, if they have previously placed a bid the previous bid amount if returned and a new one is set
     * @param _proposedRevealAmount the actual amount bid
     * @param _salt the salt used in combination with the amount to reveal the bid
     */
    function revealBid(uint256 _proposedRevealAmount, uint256 _salt)
    onlyWhenRevealingOpen
    public
    returns (bool) {
        Bidder storage bidder = participants[msg.sender];

        // Ensure users results valid
        require(keccak256(abi.encodePacked(_proposedRevealAmount, _salt)) == bidder.sealedBid, "Unable to find matching sealed bid");

        // Ensure not already revealed
        require(!bidder.hasRevealed, "User already revealed bid");
        bidder.hasRevealed = true;

        bool hasCommittedSufficientFunds = _proposedRevealAmount <= bidder.tokenCommitment;

        // Insufficient funds to cover bid
        if (!hasCommittedSufficientFunds) {
            require(!hasCommittedSufficientFunds, "Insufficient funds to cover bid");

            // TODO cheater - how to penalise?
            return true;
        }

        bool reservePriceMet = _proposedRevealAmount >= reservePrice;

        // TODO is this possible - ensure test coverage
        // Revealed amount is less than reserve
        if (!reservePriceMet) {
            require(!reservePriceMet, "Reserve price not mee=t");

            // TODO cheater - how to penalise?
            return true;
        }

        // Record the actual revealed amount
        bidder.revealedBid = _proposedRevealAmount;

        // Work out the over commitment
        uint256 overCommittedAmount = bidder.tokenCommitment.sub(_proposedRevealAmount);

        // Ensure balance is set to revealed amount
        bidder.tokenCommitment = _proposedRevealAmount;

        // Send back the over committed amount
        if (overCommittedAmount > 0) {
            require(IERC20(paymentToken).transferFrom(address(this), msg.sender, overCommittedAmount), "Unable to send back over committed funds");
        }

        // TODO keep ordered list of revealed bids

        return true;
    }

    //    // TODO handle burn condition when someone does not reveal in time?¬
    //
    //    function resultAuction() public {
    //        require(now > endOfRevealing, "Reveal period has not closed yet");
    //        require(owner == msg.sender, "Cannot only be resulted by the auction creator");
    //        require(!auctionResulted, "Already resulted");
    //
    //        // Ensure auction is resulted
    //        auctionResulted = true;
    //
    //        // TODO How to handle when not enough bids made?
    //
    //        for (uint i = 0; i < participants.length; i++) {
    //            Bidder storage bidder = participants[i];
    //
    //            // Place revealed list into a order list based on amount committed
    //
    //        }
    //
    //        // send balance to auction creator
    //        // all others can be penalised
    //    }
    //
    //    function closeAuction() public {
    //        require(owner == msg.sender, "Cannot only be resulted by the auction creator");
    //        require(auctionResulted, "Auction not resulted yet");
    //        require(!auctionClosed, "Auction already closed");
    //
    //        // Ensure auction is now closed
    //        auctionClosed = true;
    //
    //        // generates X number of NFTS for those who won
    //    }


    /////////////////////
    // Utility methods //
    /////////////////////

    function getParticipant(address _bidder)
    public view
    returns (uint256 tokenCommitment, bytes32 sealedBid, uint256 revealedBid, bool hasRevealed) {
        Bidder memory bidder = participants[_bidder];
        return (
        bidder.tokenCommitment,
        bidder.sealedBid,
        bidder.revealedBid,
        bidder.hasRevealed
        );
    }

}
