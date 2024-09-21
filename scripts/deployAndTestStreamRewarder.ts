import { ethers as Ethers, network } from "hardhat";
import { ethers, logger } from "ethers";

import {CustomStreamRewarder, CustomStreamRewarder__factory, ERC20, ERC20__factory, ReceiptToken, ReceiptToken__factory} from "../typechain-types";

const ARBContractAddress = "0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1";
const ARBWale = "0x42d0ed91b55065fABCfB9ab3516437D01430C0E6";
let admin: any, alice:any, bob: any;

const moveTime = async function (secToMove: number) {
  await network.provider.send("evm_increaseTime", [secToMove]);
  await network.provider.send("evm_mine", []);  
  console.log("moved seconds: ", secToMove);
};

const fundWallets = async(receiptTokenAddress: string, rewardTokenAddress: string) =>{
  // Fund whale with some ETH
  await admin.sendTransaction({ to: ARBWale, value: ethers.utils.parseEther("10") });

  const rewardToken = ERC20__factory.connect(rewardTokenAddress, admin);
  const receiptToken = ReceiptToken__factory.connect(receiptTokenAddress, admin);

  // impersonate whale
  await network.provider.request({ method: "hardhat_impersonateAccount", params: [ARBWale]});
  const whaleWallet = await Ethers.provider.getSigner(ARBWale);

  // send reward tokens from whale to Admin
  await rewardToken.connect(whaleWallet).transfer(admin.address, ethers.utils.parseEther("100000"));
  
  // Mint receipt tokens to alice & bob
  await receiptToken.connect(admin).mint(alice.address, ethers.utils.parseEther("1000"));
  await receiptToken.connect(admin).mint(bob.address, ethers.utils.parseEther("5000"));

}

const deployContracts = async() =>{
  const [admin, player1, player2] = await Ethers.getSigners();
    
    const receiptToken: ReceiptToken = await  new ReceiptToken__factory(admin).deploy("Test Token 1","TT1");
    const streamRewarder: CustomStreamRewarder = await new CustomStreamRewarder__factory(admin)
      .deploy(receiptToken.address, admin.address, 86400 * 7, "1000500000000");
    await receiptToken.setRewarder(streamRewarder.address);

    console.log("Receipt Token Deployed:", receiptToken.address);
    console.log("Stream Rewarder Deployed:", streamRewarder.address);
    return [receiptToken.address, streamRewarder.address];
}

const simulation = async(addresses: string[]) => {
  
  const receiptToken: ReceiptToken = ReceiptToken__factory.connect(addresses[0],admin);
  const rewarder: CustomStreamRewarder = CustomStreamRewarder__factory.connect(addresses[1], admin);
  const ARBToken: ERC20 = ERC20__factory.connect(ARBContractAddress, admin);

  // Fund admin with reward tokens(ARB token), alice & bob with receipt tokens
  await fundWallets(receiptToken.address, ARBContractAddress);

  // Queue rewards into rewarder:
  await ARBToken.connect(admin).approve(rewarder.address, ethers.utils.parseEther("1000"));
  await rewarder.connect(admin).queueNewRewards(ethers.utils.parseEther("1000"), ARBContractAddress);

  // Move Time 
  await moveTime(86400);
  await rewarder.updateFor(alice.address);
  console.log("Rewards earned:", await rewarder.allEarned(alice.address));
  
  // Move Time 
  await moveTime(86400);
  await rewarder.updateFor(alice.address);
  console.log("Rewards earned:", await rewarder.allEarned(alice.address));
  
}

async function main() {
    
  [admin, alice, bob] = await Ethers.getSigners();
  // Deploy Contracts--
  const deployedAddresses = await deployContracts();

  // Simulation--
  await simulation(deployedAddresses);
    
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
