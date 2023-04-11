import { ethers, upgrades } from "hardhat";

async function main() {
  const signers = await ethers.getSigners();
  console.log(signers.length);
  console.log(signers[1].address)

  const Stake2Follow = await ethers.getContractFactory("Stake2Follow");
  const sf = await upgrades.upgradeProxy('0x30c5D433d515A17948d5CFAA0c55E52Ea7FdBaFA', Stake2Follow)
  console.log(`Deployed upgraded: ${sf.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});