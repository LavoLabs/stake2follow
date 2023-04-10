import { ethers, upgrades } from "hardhat";

async function main() {
  const decimal = ethers.BigNumber.from('1000000');

  const signers = await ethers.getSigners();
  console.log(signers.length);
  console.log(signers[0].address)

  const Stake2Follow = await ethers.getContractFactory("Stake2Follow");
  const sf = await upgrades.deployProxy(Stake2Follow, [
    decimal.mul(5), 
    5, 
    10, 
    5, 
    '0xE097d6B3100777DC31B34dC2c58fB524C2e76921', 
    signers[1].address, 
    signers[0].address
  ]);
 
  await sf.deployed();

  console.log(`Deployed at ${sf.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});