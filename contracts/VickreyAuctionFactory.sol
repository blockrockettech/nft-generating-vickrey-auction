pragma solidity ^0.5.12;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./VickreyAuction.sol";

contract VickreyAuctionFactory {

    // TODO probs best created through a AuctionFactory contract so can easily watch and subgraph it

    address public factoryOwner;

    IERC20 public paymentToken;
    IERC721 public nftMinter;

    mapping(address => VickreyAuction) auctions;

    event AuctionCreated(
        VickreyAuction _auction,
        IERC20 _paymentToken,
        IERC721 _nftMinter,
        address _creator
    );

    constructor(IERC20 _paymentToken, IERC721 _nftMinter) public {
        factoryOwner = msg.sender;
        paymentToken = _paymentToken;
        nftMinter = _nftMinter;
    }

    function createAuction(
        uint256 _reservePrice, // Auction base price e.g. $30
        uint256 _totalItemsForSale, // Max allowed items in the auction
        uint256 _biddingPeriod, // How long is the action going to last for
        uint256 _revealingPeriod // How long in seconds after auction close is the bidder allowed to reveal there bid for
    ) public {
        require(factoryOwner == msg.sender, "Unable to create auction");

        VickreyAuction auction = new VickreyAuction(
            paymentToken,
            nftMinter,
            _reservePrice,
            _totalItemsForSale,
            _biddingPeriod,
            _revealingPeriod,
            msg.sender
        );

        auctions[address(auction)] = auction;

        emit AuctionCreated(auction, paymentToken, nftMinter, msg.sender);
    }

}
