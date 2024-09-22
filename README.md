To start, first install all the packages: use `npm i --f`

To run the fork mainnet script that tests the rewarder in best case usage-
1. Fork ethereum mainnet by `npx hardhat node --fork https://eth.llamarpc.com --port 8550`
2. Run the script on the forked mainnet in a separate terminal by: `hardhat run --network ethlocalhost scripts\deployAndTestStreamRewarder.ts`

To run the local tests which test the rewarder in all cases of usage:
1. First create a chain by: `npx hardhat node`
2. Run the test file on the chain: `npx hardhat test --network localhost`


The Custom Duration Based Stream Rewarder

Specifications-

Rewarder has a fixed duration, send some rewards to the rewarder and it will stream those rewards to all the share holders(holders of the receipt token) for the duration specified in the rewarder, after duration, no rewards streamed.
Upon sending more rewards, the time for the end of duration is updated in rewarder e.g. duration is 7 days, rewards first sent on day 1(end day is day 8), rewards sent to rewarder again on 3rd day(now the end day becomes day 10).
The reward rate is not constant but increases parabolically: according to the equation at2 + bt + c where t is the current time stamp.
If the existing rewards have not expired and new queue of rewards is done, what happens is the amount left to be streamed + the new queue amount is taken as the total rewards queued and new reward rates are according to that.

Limitation: the c parameter is NOT configuration because of a mathematical restriction because of the above specs, can refer to the mathematics to see why.


Mathematics:


The y-axis signifies the reward rate and the x-axis signifies the timestamp.
As time increases the reward rate increase parabolically.

r(t) = at^2 + bt + c

r is a function of t.
Area under the curve from t1 to t2 bw the curve and the x-axis gives the rewards streamed by the stream rewarder in the duration from t1 to t2.
To calculate the amount of the rewards streamed we can do a mathematical integration on the r(t) = at^2 + bt + c
And by putting the limits of integration as t1 and t2 we will get the total rewards streamed.

Reward rate at any instant can be calculated by using the r(t) = at^2 + bt + c formula only.

Limitation: Upon observing carefully we can see that if all the a, b, c are fixed before then the graph is fixed, it will always be same no matter how much rewards are queued to the rewarder so even if you sent more rewards or less rewards, for the given duration, the area under curve for a certain t1 and t2 would be same i.e. sending more rewards does not matter anymore.

But if you consider that c is not fixed but calculated whenever rewards are queued, then the graph can actually just retain shape but move up and down, so more rewards are queued, the graph moves up and the area under curve increases, less rewards queued, graph moves down, area under curve and hence the total rewards streamed in the duration are reduced.

Hence, if we can design an algorithm that calculates how much we need to move the graph up or down to stream the given amount of rewards in the duration.
Or mathematically, we calculate the value of c so that the area under the curve in the duration is equal to the amount of rewards that have been queued, then we’ll be good to go.

This can easily be achieved as we know the area = queued amount of rewards which we know and let’s call x

x= area under the curve from queue time stamp t1 to queue timestamp + duration t2

For finding the area, we’ll have to integrate 
r(t) = at^2 + bt + c from t1 to t2

Specify non-zero ‘a’ to get a parabolic reward rate.
Specify ‘a’ as zero and non-zero ‘b’ to get a linear reward rate.
Specify both ‘a’ & ‘b’ as zero to get a constant reward rate.

The constant reward rate does not mean the reward rate will be same if the amount of rewards sent to the rewarder are different.
If the rewarder is used for constant reward rate it means that the reward rate will be constant until the next queue of rewards of the expiry of existing rewards. 

Refero to the doc for more details: https://docs.google.com/document/d/1VOkuZ4MD8QEy3-mfXXA_dZ_Jo5Q2HLUs_oG33NQ4KBc
