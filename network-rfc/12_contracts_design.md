# Portal System


### Portal Pool Creation and SQD Collection

The Portal System begins when a Portal Operator creates a new portal pool through the PortalFactory by specifying key parameters including the maximum capacity (amount of SQD tokens), deposit deadline, payment token, and "budget".

The portal operator allocation (contribution by the deployer) will be determined by the maximum capacity that the portal operator is seeking.

The maximum capacity parameter defines the total amount of SQD that can be staked into the portal pool. This can be configured by the portal operator during creation and can be increased later if needed. The contract requires this amount to be higher than the minimum stake threshold (set by protocol governance/gateway registery contract) for portal registration.

The factory deploys a single PortalPool contract, an upgradeable instance that combines both the core distribution logic and SQD vault functionality into one unified contract. 
Once deployed, SQD token providers can stake their tokens directly into the PortalPool by calling the stake function with the portal pool address and desired amount. 

During this collection phase, the portal pool remains in a "Collecting" state where it accumulates SQD deposits from multiple providers until either the maximum capacity is reached or the deposit deadline passes. 
If sufficient SQD is collected before the deadline (meeting the minimum threshold for portal registration), the portal operator can trigger the activate function to transition the portal pool to its active distribution phase.

However, if the deadline expires without reaching the minimum threshold required for portal registration, the portal pool is marked as failed, triggering a full refund of both the operator's budget and all staked SQD tokens back to their respective owners.

### Active Distribution and Fee Routing
Once activated, the portal pool enters its Active state where it begins distributing 

Throughout this active period, the portal operator can call the distribute function to inject tokens into the contract, which will be distributed across SQD providers etc. 
This amount is distributed based on the FeeRouterModule, a separate admin-controlled contract responsible for splitting the fees according to configurable basis point allocations (configurable k% goes to the treasury and the rest goes to SQD providers).

The FeeRouterModule holds the actual BPS.
 During both the staking and distribution phases, the system can trigger external Hooks at key moments (before and after staking, distribution, and exits), allowing for customized behavior such as additional protocol token rewards layered on top of base distributions etc.
 Similar to UniswapV4 Hooks.


The portal scales down its capacity as SQD is withdrawn but continues operating until the minimum threshold is breached.


**Two-Step Withdrawal Process:**

1. **Portal Pool Exit Delay**: Exits are subject to a time-delay mechanism designed to prevent sudden liquidity shocks. The exit delay consists of a base period of 1 epoch plus a percentual delay calculated by the amount being withdrawn. The system allows a maximum of 1% of the total portal pool liquidity to exit per epoch, meaning if a provider wants to exit 5% of the liquidity, they must wait 1 epoch (base) plus 5 additional epochs (one epoch per 1% of liquidity), totaling 6 epochs before their full withdrawal is processed. Providers can withdraw unlocked portions incrementally (1% per epoch) rather than waiting for the full delay period to complete.

2. **Liquid Unstaking from Registration**: Once the exit delay period completes and the withdrawal is processed by the portal pool contract, the Portal Registration Contract handles the actual unstaking. Since the registration contract supports liquid staking, the unstaking happens immediately without additional lock periods. The compute units allocated to the portal are reduced proportionally as SQD is unstaked.

For example, if a provider holds 10% of the portal pool's total SQD and wants to exit their entire position, they would need to wait 1 base epoch + 10 epochs (for the 10% withdrawal) = 11 epochs total in the portal pool.

**Importantly, once a provider requests an exit, they stop earning rewards on the requested exit amount during the entire waiting period**

New SQD providers can enter the portal pool at any time, including when existing providers have requested exits. This allows for seamless replacement and maintains liquidity continuity in the pool. When new providers stake, the portal registration contract immediately increases the allocated compute units proportionally.

Throughout this entire process, the system maintains upgradeability through the proxy pattern (allowing the factory admin to deploy improved implementations without affecting existing portal pools), adjustable fee distributions (admins can modify the FeeRouterModule configuration to change allocation percentages), and emergency controls (pausing functionality at both the factory and individual portal pool levels for security purposes).

---

## State Transitions

```
Collecting → Active → Closed
     ↓
  Failed
```

- **Collecting**: Portal pool accepting SQD deposits, waiting to reach minimum threshold before deadline
- **Active**: Minimum threshold met, portal registered and distributing tokens when injected. Portal continues operating as long as staked amount remains above minimum threshold, with compute units scaling proportionally.
- **Failed**: Deadline passed without reaching minimum threshold, full refunds enabled
- **Closed**: Portal pool closed?


### To Discuss

1. **Liquid Stake Tokens (LST) vs NFTs**:
   - SQD provider positions could be represented as Liquid Stake Tokens (fungible) or NFTs (non-fungible)
   - Issue: LSTs would be tied to each portal pool (potentially 100+ different tokens if many portals exist)



### Portal Registration Contract (V2)

A new simplified Portal Registration Contract will be created to replace the current GatewayRegistry for portal pool operations. This contract is designed specifically for the portal pool system.
