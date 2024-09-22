To start, first install all the packages: use `npm i --f`
Then fork ethereum mainnet by `npx hardhat node --fork https://eth.llamarpc.com --port 8550`
Then run the script on the forked mainnet in a separate terminal by: `hardhat run --network ethlocalhost scripts\deployAndTestStreamRewarder.ts`

To run the local tests: first create a chain by: `npx hardhat node` 
TO run the test file on the chain: `npx hardhat test --network localhost`
