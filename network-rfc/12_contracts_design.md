# Portal System


### Portal Pool Creation and SQD Collection

The Portal System begins when a Portal Operator creates a new portal pool through the PortalFactory by specifying key parameters including the target amount of SQD tokens needed, deposit deadline, payment token, "budget".

The portal operator allocation (contribution by the deployer) will be determined by the target amount that the portal operator is seeking.

We are collecting 120% of the amount that will be set by SQD (configurable by governance).

The factory deploys a single PortalProxy contract, an upgradeable instance that combines both the core distribution logic and SQD vault functionality into one unified contract. 
Once deployed, SQD token providers can stake their tokens directly into the PortalProxy by calling the stake function with the portal pool address and desired amount. 

During this collection phase, the portal pool remains in a "Collecting" state where it accumulates SQD deposits from multiple providers until either the target amount is reached or the deposit deadline passes. 
If the target is met before the deadline, the portal operator can trigger the activate function to transition the portal pool to its active distribution phase.

However, if the deadline expires without reaching the target, the portal pool is marked as failed, triggering a full refund of both the operator's budget and all staked SQD tokens back to their respective owners.

### Active Distribution and Fee Routing
Once activated, the portal pool enters its Active state where it begins distributing 

Throughout this active period, the portal operator can call the distribute function to inject tokens into the contract, which will be distributed across SQD providers etc. 
This amount is distributed based on the FeeRouterModule, a separate admin-controlled contract responsible for splitting the fees according to configurable basis point allocations (configurable k% goes to the treasury and the rest goes to SQD providers).

The FeeRouterModule holds the actual BPS.
 During both the staking and distribution phases, the system can trigger external Hooks at key moments (before and after staking, distribution, and exits), allowing for customized behavior such as additional protocol token rewards layered on top of base distributions etc.
 Similar to UniswapV4 Hooks.

### Reward Claims, Exits, and Closure

While the portal pool is active, SQD providers can claim their proportional share of accumulated rewards at any time by calling the claimRewards function on the PortalProxy, which calculates their share based on their staked balance relative to the total tokens in the portal pool and transfers the corresponding tokens to them. The portal pool continues distributing as long as the portal operator injects tokens through the distribute function, with all distributions based on the FeeRouterModule configured splits.

When SQD providers stake their tokens into the portal pool, they lock them for a minimum duration period (set by protocol governance). 
After this minimum lock period expires, providers can request to exit the portal pool by calling requestExit with their desired withdrawal amount. 
However, exits are subject to a time-delay mechanism designed to prevent sudden liquidity shocks: 
the exit delay consists of a base period of 1 epoch plus a percentual delay calculated by the amount being withdrawn. 
The system allows a maximum of 1% of the total portal pool liquidity to exit per epoch, meaning if a provider wants to exit 5% of the liquidity, they must wait 1 epoch (base) plus 5 additional epochs (one epoch per 1% of liquidity), totaling 6 epochs before their full withdrawal is processed.
Providers can withdraw unlocked portions incrementally (1% per epoch) rather than waiting for the full delay period to complete. 
For example, if a provider holds 10% of the portal pool's total SQD and wants to exit their entire position, they would need to wait 1 base epoch + 10 epochs (for the 10% withdrawal) = 11 epochs total. This mechanism ensures gradual exits and maintains portal pool stability while still allowing providers to eventually withdraw their staked tokens along with any accumulated rewards.

**Importantly, once a provider requests an exit, they stop earning rewards on the requested exit amount during the entire waiting period**

New SQD providers can enter the portal pool at any time, including when existing providers have requested exits. This allows for seamless replacement and maintains liquidity continuity in the pool.

Throughout this entire process, the system maintains upgradeability through the proxy pattern (allowing the factory admin to deploy improved implementations without affecting existing portal pools), adjustable fee distributions (admins can modify the FeeRouterModule configuration to change allocation percentages), and emergency controls (pausing functionality at both the factory and individual portal pool levels for security purposes).



### Exit Delay Formula
```
Total Exit Delay = Base Delay + Percentual Delay
Base Delay = 1 epoch (mandatory for all exits)
Percentual Delay = (Withdrawal Amount / Total Portal Pool Liquidity) × 100 epochs
```


---

## State Transitions

```
Collecting → Active → Closed
     ↓
  Failed
```

- **Collecting**: Portal pool accepting SQD deposits, waiting to reach target before deadline
- **Active**: Target met, distributing tokens when injected.
- **Failed**: Deadline passed without reaching target, full refunds enabled
- **Closed**: Portal pool closed?


### To Discuss
- The operator's budget over the specified duration using a time-based linear vesting mechanism calculated as budget divided by duration to determine the payment rate per second in beginning? 

1. **120% Collection Split**:
   - Portal pool collects 120% of the target amount from SQD providers
   - Where does the split happen?

2. **Withdrawal Coordination**:
   - **GatewayRegistry has its own lock period**: 
     ```solidity
     require(operators[msg.sender].stake.lockEnd <= block.number, "Stake is locked");
     ```
   - **Portal pool has epoch-based exit delays**: Base 1 epoch + percentual delay (1% per epoch)
   - **Problem**: Two separate delay mechanisms
     - When a provider requests exit from Portal pool, Portal pool needs to unstake from GatewayRegistry
     - But GatewayRegistry requires `lockEnd <= block.number` to unstake
    - How can we synchronize these two timelines? Should we base it on the minimum lock period plus a percentage of the GatewayRegistry lock? (Minimum + as Base the GatewayRegistry lock + percentual lock?)

**Should we actually take this into account now? Any focus on developing an upgraded (V2) version of the current contracts that's more compatible with the Portal pool contract?
The Portal pool Contract wille be anyways upgradealbe so we can go with the current implementation for now and i can design the contract, so it fits also the V2 later.**
