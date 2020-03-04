const {BN, expectRevert, expectEvent, constants, time} = require('@openzeppelin/test-helpers');
const {ZERO_ADDRESS} = constants;
require('chai').should();

const VickreyAuction = artifacts.require('./VickreyAuction.sol');
const SimpleNft = artifacts.require('./SimpleNft.sol');
const MockDai = artifacts.require('./MockDAI.sol');

const toEthBN = function (ethVal) {
    return new BN(web3.utils.toWei(ethVal, 'ether').toString());
};

contract('VickreyAuction tests', function ([creator, alice, bob, ...accounts]) {


    beforeEach(async function () {
        this.simpleNft = await SimpleNft.new({from: creator});
        this.mockDai = await MockDai.new({from: creator});

        this.reservePrice = toEthBN('30'); // $30
        this.totalItemsForSale = new BN(10);
        this.biddingPeriod = new BN(172800); // 48hrs
        this.revealingPeriod = new BN(86400); // 24hrs

        this.now = await time.latest();

        this.auction = await VickreyAuction.new(
            this.mockDai.address,
            this.simpleNft.address,
            this.reservePrice,
            this.totalItemsForSale,
            this.biddingPeriod,
            this.revealingPeriod,
            creator,
            {from: creator});
    });

    describe('Auction setup correctly', async function () {

        it('reservePrice()', async function () {
            const reservePrice = await this.auction.reservePrice();
            reservePrice.should.be.bignumber.eq(this.reservePrice);
        });

        it('endOfBidding()', async function () {
            const endOfBidding = await this.auction.endOfBidding();
            endOfBidding.should.be.bignumber.eq(this.now.add(this.biddingPeriod));
        });

        it('endOfRevealing()', async function () {
            const endOfRevealing = await this.auction.endOfRevealing();
            endOfRevealing.should.be.bignumber.eq(this.now.add(this.biddingPeriod).add(this.revealingPeriod));
        });

        it('totalItemsForSale()', async function () {
            const totalItemsForSale = await this.auction.totalItemsForSale();
            totalItemsForSale.should.be.bignumber.eq(this.totalItemsForSale);
        });

        it('paymentToken()', async function () {
            const paymentToken = await this.auction.paymentToken();
            paymentToken.should.be.eq(this.mockDai.address);
        });

        it('nftMinter()', async function () {
            const nftMinter = await this.auction.nftMinter();
            nftMinter.should.be.eq(this.simpleNft.address);
        });

        it('Auction creator is setup as already revealed participant', async function () {
            const {
                tokenCommitment,
                sealedBid,
                revealedBid,
                hasRevealed
            } = await this.auction.getParticipant(creator);

            tokenCommitment.should.be.bignumber.eq('0');
            sealedBid.should.be.eq('0x0000000000000000000000000000000000000000000000000000000000000000');
            revealedBid.should.be.bignumber.eq('0');
            hasRevealed.should.be.eq(true);
        });

    });

});
