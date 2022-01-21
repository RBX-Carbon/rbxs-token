import { expect } from "chai";
import { artifacts, ethers } from "hardhat";

import { BN, constants, expectEvent, expectRevert } from '@openzeppelin/test-helpers';
const { ZERO_ADDRESS } = constants;

import { shouldBehaveLikeERC20, shouldBehaveLikeERC20Transfer, shouldBehaveLikeERC20Approve } from './erc20.js';

const RBXS = artifacts.readArtifact('RBXS');

describe("Greeter", function () {
  it("Should return the new greeting once it's changed", async function () {
    const Greeter = await ethers.getContractFactory("Greeter");
    const greeter = await Greeter.deploy("Hello, world!");
    await greeter.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
});

contract('RBXS', function ([_, initialHolder, recipient, anotherAccount]) {
  const initialSupply = new BN(100);

  beforeEach(async function () {
    this.token = await RBXS.new(100,"Consensys",10,"CSS",{'from':initialHolder});
  });

  shouldBehaveLikeERC20('ERC20', initialSupply, initialHolder, recipient, anotherAccount);
});