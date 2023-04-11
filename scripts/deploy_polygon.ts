import { ethers, upgrades } from "hardhat";

async function main() {
  const decimal = ethers.BigNumber.from('1000000000000000000');

  const signers = await ethers.getSigners();
  console.log(signers.length);
  console.log(signers[0].address)

  const Stake2Follow = await ethers.getContractFactory("Stake2Follow");
  const sf = await upgrades.deployProxy(Stake2Follow, [
    decimal.mul(2), 
    10, 
    0, 
    20, 
    '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270', 
    '0x509445190B91D646C2e6973409894f39Ba5d1c52', 
    '0xeDB79a63c3A888D806463D82f7ca29511e5437AD'
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