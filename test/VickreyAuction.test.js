const {BN, expectRevert, expectEvent, constants, time, ether} = require('@openzeppelin/test-helpers');
const {ZERO_ADDRESS} = constants;
require('chai').should();

const VickreyAuction = artifacts.require('./VickreyAuction.sol');
const SimpleNft = artifacts.require('./SimpleNft.sol');
const MockDai = artifacts.require('./MockDAI.sol');

contract('VickreyAuction tests', function ([creator, alice, bob, ...accounts]) {

    const _100_DAI = ether('100');
    const _30_DAI = ether('30');
    const _50_DAI = ether('50');
    const _29_DAI = ether('29');

    const _1_HOUR = new BN('3600');

    beforeEach(async function () {
        this.simpleNft = await SimpleNft.new({from: creator});
        this.mockDai = await MockDai.new({from: creator});

        this.reservePrice = _30_DAI;
        this.totalItemsForSale = new BN(10);
        this.biddingPeriod = new BN(172800); // 48hrs
        this.revealingPeriod = new BN(86400); // 24hrs

        this.auction = await VickreyAuction.new(
            this.mockDai.address,
            this.simpleNft.address,
            this.reservePrice,
            this.totalItemsForSale,
            this.biddingPeriod,
            this.revealingPeriod,
            creator,
            {from: creator});

        this.now = await time.latest();

        // give bob & alice some dollar
        await this.mockDai.mint(bob, _100_DAI);
        this.mockDai.approve(this.auction.address, _100_DAI, {from: bob});

        await this.mockDai.mint(alice, _100_DAI);
        this.mockDai.approve(this.auction.address, _100_DAI, {from: alice});
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

    describe('Placing a bid', async function () {

        describe('validation checks', async function () {

            // TODO test for unable to escrow funds approval failure

            it('fails if commitment less than threshold', async function () {
                const sealedBid = await generateSealedBid.call(this, _50_DAI, 'password');
                await expectRevert(
                    this.auction.placeBid(sealedBid, _29_DAI, {from: alice}),
                    'Bid does not meet reserve price'
                );
            });

            it('fails if sealed bid looks blank', async function () {
                const sealedBid = web3.eth.abi.encodeParameter('bytes32', '0x0');
                await expectRevert(
                    this.auction.placeBid(sealedBid, _50_DAI, {from: alice}),
                    'Sealed bid is blank'
                );
            });

            it('fails if creator tried to place bid', async function () {
                // const sealedBid = await generateSealedBid(_50_DAI, 'password');
                const sealedBid = await generateSealedBid.call(this, _50_DAI, 'password');
                await expectRevert(
                    this.auction.placeBid(sealedBid, _50_DAI, {from: creator}),
                    'Creator cannot bid on their own items'
                );
            });

            it('fails if bidding has closed', async function () {

                // Move period past bidding period
                await time.increaseTo(this.now.add(this.biddingPeriod));

                const sealedBid = await generateSealedBid.call(this, _50_DAI, 'password');
                await expectRevert(
                    this.auction.placeBid(sealedBid, _50_DAI, {from: alice}),
                    'Auction bidding time period has closed'
                );
            });

        });

        describe('on successful bid', async function () {

            beforeEach(async function () {
                this.sealedBid = await generateSealedBid.call(this, _50_DAI, 'password');
                await this.auction.placeBid(this.sealedBid, _100_DAI, {from: alice});
            });

            it('should escrow funds', async function () {
                const balanceOfAuction = await this.mockDai.balanceOf(this.auction.address);
                balanceOfAuction.should.be.bignumber.eq(_100_DAI);
            });

            it('participant data is stored', async function () {
                const {
                    tokenCommitment,
                    sealedBid,
                    revealedBid,
                    hasRevealed
                } = await this.auction.getParticipant(alice);

                tokenCommitment.should.be.bignumber.eq(_100_DAI);
                sealedBid.should.be.eq(this.sealedBid);
                revealedBid.should.be.bignumber.eq('0');
                hasRevealed.should.be.eq(false);
            });

            describe('can withdraw bid', async function () {

                beforeEach(async function () {
                    await this.auction.withdraw({from: alice});
                });

                it('funds sent back to bidder', async function () {
                    const balanceOfAlice = await this.mockDai.balanceOf(alice);
                    balanceOfAlice.should.be.bignumber.eq(_100_DAI);
                });

                it('no funds left in escrow', async function () {
                    const balanceOfAuction = await this.mockDai.balanceOf(this.auction.address);
                    balanceOfAuction.should.be.bignumber.eq('0');
                });

                it('participant data is stored', async function () {
                    const {
                        tokenCommitment,
                        sealedBid,
                        revealedBid,
                        hasRevealed
                    } = await this.auction.getParticipant(alice);

                    tokenCommitment.should.be.bignumber.eq('0');
                    sealedBid.should.be.eq('0x0000000000000000000000000000000000000000000000000000000000000000');
                    revealedBid.should.be.bignumber.eq('0');
                    hasRevealed.should.be.eq(false);
                });
            });

            describe('can reveal bid', async function () {

                describe('when bidding time not passed', async function () {
                    it('should fail to reveal bid', async function () {
                        await expectRevert(
                            this.auction.revealBid(123, 123, {from: alice}),
                            'Reveal stage not started'
                        );
                    });
                });

                describe('when reveal time has passed', async function () {
                    it('should fail to reveal bid', async function () {
                        await time.increaseTo(this.now.add(this.biddingPeriod).add(this.revealingPeriod));

                        await expectRevert(
                            this.auction.revealBid(123, 123, {from: alice}),
                            'Reveal stage passed'
                        );
                    });
                });

                describe('when bidding time has passed', async function () {
                    beforeEach(async function () {
                        // Move period past bidding period
                        await time.increaseTo(this.now.add(this.biddingPeriod).add(_1_HOUR));

                        await this.auction.revealBid(_50_DAI, web3.utils.toHex('password'), {from: alice});
                    });

                    it('fails when reveal bid is not correct', async function () {
                        await expectRevert(
                            this.auction.revealBid(_50_DAI, web3.utils.toHex('Password'), {from: alice}),
                            'Sealed bid doesnt match'
                        );
                    });

                    it('updates participant state', async function () {
                        const {
                            tokenCommitment,
                            sealedBid,
                            revealedBid,
                            hasRevealed
                        } = await this.auction.getParticipant(alice);

                        tokenCommitment.should.be.bignumber.eq(_100_DAI);
                        sealedBid.should.be.eq(this.sealedBid);
                        revealedBid.should.be.bignumber.eq(_50_DAI);
                        hasRevealed.should.be.eq(true);
                    });

                    it('returns over commitment to alice', async function () {
                        const balanceOfAuction = await this.mockDai.balanceOf(alice);
                        balanceOfAuction.should.be.bignumber.eq(_50_DAI);
                    });

                    it('contract balance updated', async function () {
                        const balanceOfAuction = await this.mockDai.balanceOf(this.auction.address);
                        balanceOfAuction.should.be.bignumber.eq(_50_DAI);
                    });

                    it('fails to reveal is already done', async function () {
                        //
                    });
                });

            });
        });

        // TODO handle cheaters

        describe('should generate sealed bid on and off chain', async function () {
            it('should match', async function () {
                const onChainBid = await generateSealedBid.call(this, _50_DAI, 'password');
                const web3Bid = await generateWeb3SealedBid.call(this, _50_DAI, 'password');
                web3Bid.should.be.eq(onChainBid);
            });
        });

    });

    async function generateSealedBid(value, salt) {
        return this.auction.generateSealedBid(value, web3.utils.toHex(salt));
    }

    async function generateWeb3SealedBid(value, salt) {
        const saltedHexValue = web3.utils.toHex(salt);
        const encoded = web3.eth.abi.encodeParameters(
            ['uint256', 'uint256'],
            [value.toString(), saltedHexValue]
        );
        return web3.utils.keccak256(encoded);
    }
});
