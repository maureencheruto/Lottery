const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("🚀 Deploying with account:", deployer.address);

  // Crowdfunding constructor args
  const name = "My Campaign";
  const description = "Demo crowdfunding project";
  const goal = hre.ethers.parseEther("1"); // 1 ETH fundraising goal
  const duration = 3600; // 1 hour in seconds

  // Deploy contract
  const Crowdfunding = await hre.ethers.getContractFactory("SimpleCrowdfund");
  const contract = await Crowdfunding.deploy(name, description, goal, duration);

  await contract.waitForDeployment(); // ethers v6
  console.log("✅ Crowdfunding deployed to:", await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
