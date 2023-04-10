import { ethers, upgrades } from "hardhat";

async function main() {
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

  console.log(`Deployed at ${sf.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});