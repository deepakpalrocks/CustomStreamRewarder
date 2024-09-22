import { CustomStreamRewarder, CustomStreamRewarder__factory, ERC20, ERC20__factory, MintableERC20, MintableERC20__factory, ReceiptToken, ReceiptToken__factory } from "../typechain-types";
import {
    getAccounts,
    getWaffleExpect,
    getRandomAccount,
  } from "../utils/test";
import { Account } from "../utils/types";
import { Blockchain, ether } from "../utils/common";
import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";
import { BigNumber as BigNumberJS } from "bignumber.js";

const expect = getWaffleExpect();

const Coefficient = (coefficient: string) => {
    return ethers.utils.parseUnits(coefficient, 12);
}

describe("Custom Stream Rewarder", async () => {

    let admin: Account;
    let Alice: Account;
    let Bob: Account;
    let Henry: Account;

    let rewarder: CustomStreamRewarder;
    let receiptToken: ReceiptToken;
    let reward1: MintableERC20;
    let reward2: MintableERC20;
    let reward3: MintableERC20;

    let blockchain: Blockchain;

    const DENOMINATOR = BigNumber.from("1000000000000");

    before(async () => {

        // Create Wallets
        [admin, Alice, Bob, Henry] = await getAccounts();
        blockchain = new Blockchain(ethers.provider);

        // Create Tokens and mint to admin
        await Initialization();
    })

    const Initialization = async () => {

        receiptToken = await new ReceiptToken__factory(admin.wallet).deploy("CustomReceiptToken", "CRT");
        reward1 = await new MintableERC20__factory(admin.wallet).deploy("Reward Token 1", "RT1");
        reward2 = await new MintableERC20__factory(admin.wallet).deploy("Reward Token 2", "RT2");
        reward3 = await new MintableERC20__factory(admin.wallet).deploy("Reward Token 3", "RT3");

        await reward1.mint(admin.address, ether(10000));
        await reward2.mint(admin.address, ether(20000));
        await reward3.mint(admin.address, ether(50000));
    }

    it("Check Initialization", async () => {

        expect(await reward1.balanceOf(admin.address)).to.equal(ether(10000));
        expect(await reward2.balanceOf(admin.address)).to.equal(ether(20000));
        expect(await reward3.balanceOf(admin.address)).to.equal(ether(50000));
    })

    it("Rewarder deploys and receipt configures correctly", async () => {

        rewarder = await new CustomStreamRewarder__factory(admin.wallet).deploy(
            receiptToken.address, 
            admin.address, 
            86400 * 7, 
            Coefficient("1.5"), 
            Coefficient("2.4")
        );
        await receiptToken.setRewarder(rewarder.address);

        expect(await rewarder.coefficient_a()).to.equal(Coefficient("1.5"));
        expect(await rewarder.coefficient_b()).to.equal(Coefficient("2.4"));
        expect(await rewarder.duration()).to.equal(86400 * 7);
        expect(await rewarder.receiptToken()).to.equal(receiptToken.address);
        expect(await receiptToken.rewarder()).to.equal(rewarder.address);
        expect(await rewarder.isRewardQueuer(admin.address)).to.equal(true);

    });

    describe("Test Reward Queuing into the rewarder", async () => {

        beforeEach(async() => {

            rewarder = await new CustomStreamRewarder__factory(admin.wallet).deploy(
                receiptToken.address, 
                admin.address, 
                86400 * 7, 
                Coefficient("1.5"), 
                Coefficient("2.4")
            );        
            
            await receiptToken.setRewarder(rewarder.address);
            await receiptToken.mint(Alice.address, ether(1000));
            await receiptToken.mint(Henry.address, ether(4000));
            await receiptToken.mint(Bob.address, ether(5000));
            
        });

        const calculateCoefficientC = (amount: BigNumber, startTime: BigNumber, endTime: BigNumber, coeff_a: BigNumber, coeff_b: BigNumber,  ) => {
            const timeDiff = endTime.sub(startTime);
            const timeSquareDiff = (endTime.mul(endTime)).sub(startTime.mul(startTime));
            const timeCubeDiff = (endTime.mul(endTime).mul(endTime)).sub(startTime.mul(startTime).mul(startTime));

            let coeff_c = (amount.sub(
                (timeCubeDiff.mul(coeff_a).div(DENOMINATOR).div(3)).add(
                    timeSquareDiff.mul(coeff_b).div(DENOMINATOR).div(2)
                )).mul(DENOMINATOR).div(timeDiff)
            );

            return coeff_c;
        }

        const calculateTotalRewardsInDuration = (startTime: BigNumber, endTime: BigNumber, coeff_a: BigNumber, coeff_b:BigNumber, coeff_c:BigNumber) =>{
            const timeDiff = endTime.sub(startTime);
            const timeSquareDiff = (endTime.mul(endTime)).sub(startTime.mul(startTime));
            const timeCubeDiff = (endTime.mul(endTime).mul(endTime)).sub(startTime.mul(startTime).mul(startTime));

            const totalRewards = ((coeff_a.mul(timeCubeDiff).div(3)).add(coeff_b.mul(timeSquareDiff.div(2))).add(coeff_c.mul(timeDiff)))

            return totalRewards.div(DENOMINATOR);
        }

        it("Coefficient 'c' gets updated correctly upon a fresh queue of rewards", async () => {

            const queueAmount = ether(1000);

            await reward1.connect(admin.wallet).approve(rewarder.address, queueAmount);
            await rewarder.connect(admin.wallet).queueNewRewards(queueAmount, reward1.address);
            const currentTimeStamp = await blockchain.getCurrentTimestamp();
            const finishTimeStamp = currentTimeStamp + 7 * 86400;

            const coeff_c_expected = await calculateCoefficientC(
                queueAmount, 
                BigNumber.from(currentTimeStamp),
                BigNumber.from(finishTimeStamp),
                Coefficient("1.5"),
                Coefficient("2.4")
            );

            const coeff_c_actual = (await rewarder.rewards(reward1.address)).coefficient_c;
            expect(coeff_c_expected).to.equal(coeff_c_actual);
            
        })

        it("Coefficient 'c' gets updated correctly upon a second queue of rewards when first DURATION is over", async () => {

            // First Queue of rewards, check c updated correctly
            const queueAmount = ether(1000);

            await reward1.connect(admin.wallet).approve(rewarder.address, queueAmount);
            await rewarder.connect(admin.wallet).queueNewRewards(queueAmount, reward1.address);
            const currentTimeStamp = await blockchain.getCurrentTimestamp();
            const finishTimeStamp = currentTimeStamp + 7 * 86400;

            const coeff_c_expected = await calculateCoefficientC(
                queueAmount, 
                BigNumber.from(currentTimeStamp),
                BigNumber.from(finishTimeStamp),
                Coefficient("1.5"),
                Coefficient("2.4")
            );

            const coeff_c_actual = (await rewarder.rewards(reward1.address)).coefficient_c;
            expect(coeff_c_expected).to.equal(coeff_c_actual);

            // Move time by 8 days to previous rewards distributed
            await network.provider.send("evm_increaseTime", [86400 * 8]);
            await network.provider.send("evm_mine");
            
            // Queue new rewards after 8 days so previous rewards DURATION expired
            await reward1.connect(admin.wallet).approve(rewarder.address, queueAmount);
            await rewarder.connect(admin.wallet).queueNewRewards(queueAmount, reward1.address);
            const currentTimeStamp2 = await blockchain.getCurrentTimestamp();
            
            const finishTimeStamp2 = currentTimeStamp2 + 7 * 86400;

            const coeff_c_expected2 = await calculateCoefficientC(
                queueAmount, 
                BigNumber.from(currentTimeStamp2),
                BigNumber.from(finishTimeStamp2),
                Coefficient("1.5"),
                Coefficient("2.4")
            );

            const coeff_c_actual2 = (await rewarder.rewards(reward1.address)).coefficient_c;
            expect(coeff_c_expected2).to.equal(coeff_c_actual2);
            
        })

        it("Coefficient 'c' gets updated correctly upon a second queue of rewards when first DURATION is NOT over", async () => {

            // First Queue of rewards, check c updated correctly
            const queueAmount = ether(1000);

            await reward1.connect(admin.wallet).approve(rewarder.address, queueAmount);
            await rewarder.connect(admin.wallet).queueNewRewards(queueAmount, reward1.address);
            const currentTimeStamp = await blockchain.getCurrentTimestamp();
            const finishTimeStamp = currentTimeStamp + 7 * 86400;

            const coeff_c_expected = await calculateCoefficientC(
                queueAmount, 
                BigNumber.from(currentTimeStamp),
                BigNumber.from(finishTimeStamp),
                Coefficient("1.5"),
                Coefficient("2.4")
            );

            const coeff_c_actual = (await rewarder.rewards(reward1.address)).coefficient_c;
            expect(coeff_c_expected).to.equal(coeff_c_actual);

            // Move time by 8 days to previous rewards distributed
            await network.provider.send("evm_increaseTime", [86400 * 4]);
            await network.provider.send("evm_mine");
            
            // Queue new rewards after 4 days so previous rewards DURATION NOT expired
            const pendingFinishTimeStamp = (await rewarder.rewards(reward1.address)).periodFinish;
            await reward1.connect(admin.wallet).approve(rewarder.address, queueAmount);
            await rewarder.connect(admin.wallet).queueNewRewards(queueAmount, reward1.address);

            const currentTimeStamp2 = await blockchain.getCurrentTimestamp();
            const finishTimeStamp2 = currentTimeStamp2 + 7 * 86400;

            const rewardsLeft = calculateTotalRewardsInDuration(
                BigNumber.from(currentTimeStamp2),
                BigNumber.from(pendingFinishTimeStamp),
                Coefficient("1.5"),
                Coefficient("2.4"),
                coeff_c_expected
            );

            const coeff_c_expected2 = await calculateCoefficientC(
                queueAmount.add(rewardsLeft), 
                BigNumber.from(currentTimeStamp2),
                BigNumber.from(finishTimeStamp2),
                Coefficient("1.5"),
                Coefficient("2.4")
            );

            const coeff_c_actual2 = (await rewarder.rewards(reward1.address)).coefficient_c;
            expect(coeff_c_expected2).to.equal(coeff_c_actual2);
            
        })

        it("Reward rate is updated correctly with time according to the ")

    });
});