import { ethers, network } from "hardhat";

async function main() {

    const [admin, player1, player2] = await ethers.getSigners();

    const streamRewarder = StreamRewarder__factory();
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
