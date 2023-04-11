import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("ResetRoundDuration", function () {
  it("roundId should still increase when reset-round-duration", async function () {

    // create erc20 token
    const Token = await ethers.getContractFactory("Token");
    const decimal = ethers.BigNumber.from('1000000000000000000');
    const token = await Token.deploy('Wrapped Matic', 'wMATIC', 18, decimal.mul(1000000));
    await token.deployed();

    const signers = await ethers.getSigners();
    console.log(signers.length);

    // create stake2follow
    const Stake2Follow = await ethers.getContractFactory("Stake2Follow");
    const sf = await upgrades.deployProxy(Stake2Follow, [
      decimal.mul(5),
      5,
      10,
      5,
      token.address,
      signers[0].address,
      signers[1].address
    ]);

    await sf.deployed();

    const cfg = await sf.getConfig()
    const genesis = cfg[4].toNumber()
    const openLength = cfg[5].toNumber()
    const freezeLength = cfg[6].toNumber()
    const gapLength = cfg[7].toNumber()

    expect((await sf.getCurrentRound()).roundId).to.equals(0)



    await sf.circuitBreaker();

    console.log('===============================')
    for (let i = 0; i < 3; i += 1) {
      const factor = 2 * (i + 1)

      // go through some time
      let passedTime = 20 * gapLength
      await time.increaseTo((await time.latest()) + passedTime);
      let roundId = (await sf.getCurrentRound()).roundId.toNumber()

      const tx = await sf.resetRoundDuration(openLength / factor, freezeLength / factor, gapLength / factor)

      //let receipt = await tx.wait();
      //console.log('round compensate: ', receipt.events[0].args.roundCompensate)
      const currentTime = await time.latest()
      const localRound = Math.floor((currentTime - genesis) / (gapLength / factor))
      console.log('local round: ', localRound)
      expect((await sf.getCurrentRound()).roundId).to.equals(roundId + 1)
      expect((await sf.compensateRoundReverse(localRound))).to.equals(roundId + 1)
      expect((await sf.compensateRound(roundId + 1))).to.equals(localRound)
    }

    for (let i = 3; i >= 1; i -= 1) {
      const factor = i == 1 ? 1 : 2 * (i - 1)
      // go through some time
      let passedTime = 20 * gapLength
      await time.increaseTo((await time.latest()) + passedTime);
      let roundId = (await sf.getCurrentRound()).roundId.toNumber()

      const tx = await sf.resetRoundDuration(openLength / factor, freezeLength / factor, gapLength / factor)

      //let receipt = await tx.wait();
      //console.log('round compensate: ', receipt.events[0].args.roundCompensate)
      const currentTime = await time.latest()
      const localRound = Math.floor((currentTime - genesis) / (gapLength / factor))
      console.log('local round: ', localRound)
      expect((await sf.getCurrentRound()).roundId).to.equals(roundId + 1)
      expect((await sf.compensateRoundReverse(localRound))).to.equals(roundId + 1)
      expect((await sf.compensateRound(roundId + 1))).to.equals(localRound)
    }


    await sf.resetRoundDurationClearHistory(openLength*2, freezeLength*2, gapLength*2)
    console.log(await sf.getConfig())
    console.log(await sf.getCurrentRound())






    console.log('===========================================================')
    //   await sf.resetRoundDuration(0.5 * 60 * 60, 0.5 * 60 * 60, 1 * 60 * 60)
    //   console.log((await sf.getCurrentRound()).roundId)

    // //   await time.increaseTo(unlockTime * 2);
    //   await sf.resetRoundDuration(10 * 60, 10 * 60, 30 * 60)
    //   console.log((await sf.getCurrentRound()).roundId)

    // //   await time.increaseTo(unlockTime * 3);
    //   await sf.resetRoundDuration(5 * 60, 3 * 60, 10 * 60)
    //   console.log((await sf.getCurrentRound()).roundId)

    //   await sf.resetRoundDuration(50 * 60, 30 * 60, 100 * 60)
    //   console.log((await sf.getCurrentRound()).roundId)

    //     await sf.resetRoundDuration(500 * 60, 300 * 60, 1000 * 60)
    //   console.log((await sf.getCurrentRound()).roundId)
  });
});