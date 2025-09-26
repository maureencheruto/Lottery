const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleLottery", function () {
  let lottery, owner, alice, bob, carol;

  beforeEach(async function () {
    [owner, alice, bob, carol] = await ethers.getSigners();
    const Lottery = await ethers.getContractFactory("SimpleLottery");
    lottery = await Lottery.deploy(ethers.utils.parseEther("0.1"), 500); // ticket price = 0.1 ETH, fee = 5%
    await lottery.deployed();
  });

  it("initializes correctly", async function () {
    expect(await lottery.ticketPrice()).to.equal(ethers.utils.parseEther("0.1"));
    expect(await lottery.ownerFeeBps()).to.equal(500);
    expect(await lottery.isOpen()).to.equal(false);
  });

  it("owner can open and close lottery", async function () {
    await lottery.openLottery(ethers.utils.parseEther("0.2"), 300);
    expect(await lottery.isOpen()).to.equal(true);
    await lottery.closeLottery();
    expect(await lottery.isOpen()).to.equal(false);
  });

  it("allows players to buy tickets", async function () {
    await lottery.openLottery(ethers.utils.parseEther("0.1"), 500);
    await lottery.connect(alice).buyTickets({ value: ethers.utils.parseEther("0.2") }); // 2 tickets
    await lottery.connect(bob).buyTickets({ value: ethers.utils.parseEther("0.1") });   // 1 ticket
    expect(await lottery.getPlayersCount()).to.equal(3);
    expect(await lottery.ticketsBought(alice.address)).to.equal(2);
    expect(await lottery.ticketsBought(bob.address)).to.equal(1);
  });

  it("rejects wrong ticket price", async function () {
    await lottery.openLottery(ethers.utils.parseEther("0.1"), 500);
    await expect(
      lottery.connect(alice).buyTickets({ value: ethers.utils.parseEther("0.15") })
    ).to.be.revertedWith("Send multiple of ticketPrice");
  });

  it("picks a winner and distributes prize", async function () {
    await lottery.openLottery(ethers.utils.parseEther("1"), 1000); // 10% fee
    await lottery.connect(alice).buyTickets({ value: ethers.utils.parseEther("1") });
    await lottery.connect(bob).buyTickets({ value: ethers.utils.parseEther("1") });
    await lottery.closeLottery();

    const balanceBeforeOwner = await ethers.provider.getBalance(owner.address);
    const balanceBeforeAlice = await ethers.provider.getBalance(alice.address);
    const balanceBeforeBob = await ethers.provider.getBalance(bob.address);

    await lottery.pickWinner();

    const balanceAfterOwner = await ethers.provider.getBalance(owner.address);
    const balanceAfterAlice = await ethers.provider.getBalance(alice.address);
    const balanceAfterBob = await ethers.provider.getBalance(bob.address);

    // Owner should receive 10% of 2 ETH = 0.2 ETH
    expect(balanceAfterOwner.sub(balanceBeforeOwner)).to.be.closeTo(
      ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.01")
    );

    // Either Alice or Bob should have received ~1.8 ETH more
    const aliceGain = balanceAfterAlice.sub(balanceBeforeAlice);
    const bobGain = balanceAfterBob.sub(balanceBeforeBob);

    expect(
      aliceGain.eq(ethers.utils.parseEther("1.8")) || bobGain.eq(ethers.utils.parseEther("1.8"))
    ).to.be.true;
  });

  it("allows emergency withdraw by owner", async function () {
    await lottery.openLottery(ethers.utils.parseEther("0.1"), 500);
    await lottery.connect(alice).buyTickets({ value: ethers.utils.parseEther("0.3") });
    const balanceBefore = await ethers.provider.getBalance(owner.address);
    await lottery.emergencyWithdraw();
    const balanceAfter = await ethers.provider.getBalance(owner.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });
});

