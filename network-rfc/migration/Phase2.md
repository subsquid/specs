# SQD Network Migration Phase 2 Technical Details

The current SQD Network contracts hold immutable references to the SQD token, hardcoded at deployment time and impossible to change. Swapping the token to RZLV requires a full redeployment of every contract in the system. Since we're redeploying anyway, we take this opportunity to introduce upgradeability across the board and fix known gas bottlenecks.

Phase 2 is split into five sub-phases. Each builds on the previous, and throughout all of them we continuously collect feedback from workers and operators to inform future upgrades.

```text
Phase 2.1 (Develop & Optimize)
  ----->
Phase 2.2 (Deployment & Parallel Launch)
  ----->
Phase 2.3 (Sunset Legacy Network)
  ----->
Phase 2.4 (Full Deprecation)
  ----->
Phase 2.5 (Post-Migration Feature Expansion, ongoing)
```

---

## Phase 2.1 - Develop Upgradeability & Gas Optimization

The first step is to prepare the contracts. No deployment happens here - this is pure development work. We convert every contract to an upgradeable architecture, fix gas bottlenecks, and patch issues.

### UUPS Over Transparent Proxy

The existing system uses TransparentUpgradeableProxy for Router and GatewayRegistry. For Phase 2 we switch everything to UUPS. The reasons:

- Lower gas per call. Transparent proxies check admin slot on every `delegatecall`. UUPS skips that.
- Simpler proxy contract. Upgrade logic lives in the implementation, not in the proxy itself.
- Standard in modern OpenZeppelin. Better tooling support.

Every contract that currently uses a constructor with immutable variables gets converted. The pattern looks like this:

```solidity
// Before (current)
contract Staking is AccessControlledPausable, IStaking {
    IERC20 public immutable token;
    IRouter public immutable router;

    constructor(IERC20 _token, IRouter _router) {
        token = _token;
        router = _router;
    }
}

// After (Phase 2)
contract StakingV2 is AccessControlledPausableUpgradeable, UUPSUpgradeable, IStaking {
    IERC20 public token;
    IRouter public router;

    function initialize(IERC20 _token, IRouter _router) external initializer {
        __AccessControlledPausableUpgradeable_init();
        __UUPSUpgradeable_init();
        token = _token;
        router = _router;
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    uint256[50] private __gap;
}
```

Key changes in each contract:
- Constructor becomes `initialize()` with `initializer` modifier.
- `immutable` variables become regular storage variables (set once in `initialize`).
- Inherits `UUPSUpgradeable` and `AccessControlUpgradeable`.
- Includes a `__gap` storage array for safe future upgrades.
- `_authorizeUpgrade()` restricted to `DEFAULT_ADMIN_ROLE`.

### Token Reference Pattern

Where the current codebase uses variable names like `SQD` (in `WorkerRegistration`, `Executable`), the new contracts use the generic name `token`.

### Naming Convention

All redeployed contracts get a V2 suffix during the transition period to avoid confusion. Once the legacy system is fully deprecated, the suffix can be dropped in a future upgrade, if necessary.

### Contract-by-Contract Changes

#### Summary Table

| Contract | Current | Phase 2 | Token Change | Gas Fix | Security Fix |
|---|---|---|---|---|---|
| Router | TransparentUpgradeableProxy | UUPS + Upgradeable AC | - | - | Add `__gap` |
| NetworkController | Constructor | UUPS + initialize | - | - | - |
| WorkerRegistration | Constructor + immutable | UUPS + initialize | `SQD` → `token` | Remove triple-filter loops | SafeERC20 |
| Staking | Constructor + immutable | UUPS + initialize | Already generic | Bound claim loop | SafeERC20 |
| RewardCalculation | Constructor + immutable | UUPS + initialize | Remove hardcoded constant | Fix double-iteration | - |
| DistributedRewardsDistribution | Constructor + immutable | UUPS + initialize | - | Enforce max batch size | - |
| RewardTreasury | Constructor + immutable | RewardTreasuryV2 already deployed in Phase 1 (`sqd-migration`) | Mutable `rewardToken` | - | SafeERC20, ReentrancyGuard |
| GatewayRegistry | TransparentUpgradeableProxy | UUPS + `__gap` | Already generic | Add batch bounds | SafeERC20 |
| EqualStrategy | Constructor | UUPS + initialize | - | - | Zero-worker div guard |
| SubequalStrategy | Constructor | UUPS + initialize | - | - | Fix duplicate worker bug |
| SoftCap | Constructor | UUPS + initialize | - | - | - |
| LinearToSqrtCap | Constructor | UUPS + initialize | - | - | - |
| Executable | Abstract, storage vars | Abstract, storage vars | `SQD` → `token` | - | Reentrancy guard |
| SubsquidVesting | Constructor + immutable | See Vesting Migration | Remove SQD check | - | Inherits Executable fixes |
| TemporaryHolding | Constructor + immutable | See Holding Migration | `SQD` → `token` | - | Inherits Executable fixes |
| VestingFactory | Constructor + immutable | UUPS + initialize | Already generic | - | - |
| TemporaryHoldingFactory | Constructor + immutable | UUPS + initialize | Already generic | - | - |
| AllocationsViewer | Constructor | Redeploy (no proxy) | - | - | - |
| MerkleDistributor | Constructor + immutable | Redeploy per-distribution | Already generic | - | - |

#### Core Infrastructure

**RouterV2.** The Router already has an `initialize()` function, so the pattern is close. The main issues:

1. It uses non-upgradeable `AccessControl` from OpenZeppelin. Swap to `AccessControlUpgradeable`.
2. Missing `__gap` array - adding state variables in future upgrades could corrupt storage.
3. Switch from TransparentUpgradeableProxy to UUPS.

The Router itself doesn't interact with tokens. It's a registry of contract addresses, so the token migration is invisible to it.

**NetworkControllerV2.** The current NetworkController has a complex constructor that sets epoch length, bond amount, lock periods, and a list of allowed vesting targets. All of this moves into `initialize()`. Parameters will be seeded to match the current live values. The `isAllowedVestedTarget` mapping gets populated with the new V2 contract addresses instead of the old ones.

#### Worker Lifecycle

**WorkerRegistrationV2.** This contract gets the most changes.

*Token rename.* The `IERC20 public immutable SQD` variable (line 37) becomes `IERC20 public token`. All references update: `SQD.transferFrom(...)` → `token.safeTransferFrom(...)`.

*Gas optimization.* The current contract has three functions that iterate the entire `activeWorkerIds` set and filter out inactive workers:

- `getActiveWorkers()` - builds an array while filtering
- `getActiveWorkerIds()` - same thing, returns IDs
- `getActiveWorkerCount()` - iterates just to count

The root cause: workers are added to `activeWorkerIds` on registration but only removed on `withdraw()`, not on `deregister()`. Between deregister and withdraw, they're in the set but inactive. Every read has to filter them out.

The fix: stop carrying stale worker IDs indefinitely. On `deregister()`, mark workers for removal at epoch boundary. Once `deregisteredAt <= block.number`, remove them from `activeWorkerIds` via a bounded cleanup path, while tracking deregistered-but-not-withdrawn workers separately for bond accounting. This preserves epoch semantics and keeps the active set clean.

*SafeERC20.* Wrap all `transfer` and `transferFrom` calls (lines 89, 131, 159) with `safeTransfer` and `safeTransferFrom`.

**StakingV2.** `IERC20 public immutable token` and `IRouter public immutable router` become regular storage variables set in `initialize()`.

*SafeERC20.* Wrap `token.transferFrom` (line 93) and `token.transfer` (line 115).

*Claim loop.* The `claim()` function iterates all of a staker's delegations (bounded by `maxDelegations`, default 100). This is acceptable but should be documented. If gas becomes a concern, the bound can be lowered via governance without redeployment (thanks to upgradeability).

**RewardCalculationV2.**

`effectiveTVL()` calls `getActiveWorkerCount()` and `getActiveWorkerIds()` separately - each iterating the full worker set. With WorkerRegistrationV2's cleaned active set, `getActiveWorkerIds()` can be read once and `.length` used for count. One call instead of two.

`router` and `stakeCap` become storage variables.

#### Reward Distribution

**DistributedRewardsDistributionV2.** `IRouter public immutable router` becomes a storage variable.

The `distribute()` function iterates `recipients[]` with a storage write per iteration. This is fundamental to how distribution works - you can't avoid writing each recipient's claimable amount. The mitigation: enforce a max batch size at the contract level (e.g., `require(recipients.length <= MAX_BATCH_SIZE)`). Callers split large distributions into multiple transactions.
Additional fixes remain in scope for this module and will be completed in the same Phase 2.1 cycle.

**RewardTreasuryV2.** Already deployed as part of Phase 1 in the `sqd-migration` repo with mutable `rewardToken`. Phase 2.1 needs wiring to `RouterV2`. If the bounded claim path above is enabled, add the matching treasury methods in that repo.

#### Gateway System

**GatewayRegistryV2.** Already upgradeable (TransparentUpgradeableProxy). The changes:

1. Switch to UUPS.
2. Add `__gap` array for future storage safety.
3. SafeERC20 on `token.transferFrom` (lines 173, 200) and `token.transfer` (line 217).
4. Add batch size limits on `register(bytes[], ...)` to prevent gas limit issues.

The token reference is already generic (`IERC20WithMetadata public token`), so no rename needed. RZLV implements `decimals()` (standard ERC20), so the `tokenDecimals = 10 ** _token.decimals()` calculation works out of the box.

**SubequalStrategyV2.** Has a known bug where `supportWorkers()` corrupts `workerCount` when duplicate worker IDs are passed. This will be fixed alongside the UUPS conversion.

**EqualStrategy, SoftCap, LinearToSqrtCap.** No major logic changes, but all get the same UUPS + initialize conversion. `EqualStrategy` also gets a guard for the zero-active-workers case to avoid division-by-zero.

#### Token Holding - Vesting and Temporary Holding

This is the hardest migration problem. Each `SubsquidVesting` and `TemporaryHolding` is a standalone contract deployed per user. They hold SQD with immutable references and active vesting schedules.

**The Problem:**
- Each vesting contract has an immutable `SQD` reference and an immutable beneficiary.
- `SubsquidVesting` explicitly blocks non-SQD tokens: `require(token == address(SQD), "Only SQD is supported")`.
- Beneficiaries may have tokens staked or delegated through the vesting contract via `execute()`.
- You can't upgrade a per-user contract that isn't behind a proxy.
- **Crucially:** there is no safe, admin-neutral extraction path for unvested tokens that preserves vesting guarantees. `release()` only releases the vested portion, `execute()` explicitly blocks calling the SQD token (`require(to != address(SQD))`), and ownership cannot be transferred. A whitelisted migrator that drains unvested balances would violate vesting policy and is explicitly disallowed.

**Recommendation: Self-Migration**

Legacy `SubsquidVesting` contracts are non-upgradeable and do not allow safe extraction of unvested SQD. They remain untouched and continue releasing SQD on their original schedules. Beneficiaries self-migrate as tokens vest:

1. Beneficiary calls `release()` on legacy `SubsquidVesting` as tokens vest.
2. Beneficiary migrates released SQD to RZLV via `SQDMigration`.
3. Beneficiary uses migrated RZLV in the new V2 network.

Treasury-funded parallel vesting is not used, to avoid double-allocation risk (beneficiary receiving treasury-funded RZLV while legacy vesting still releases SQD that can later be migrated to additional RZLV).

### Risk: Legacy vesting/holding migration remains long-tail operational risk
- migration timeline depends on vesting schedules.

**TemporaryHolding Migration.** TemporaryHolding contracts have a different release mechanic than vesting: `release()` sends all funds to the `admin` address (not the beneficiary). Before `lockedUntil`, only the beneficiary can call `execute()` to interact with the network; after `lockedUntil`, the admin takes control. The migration path depends on lock status:

- **Already unlocked (`lockedUntil` has passed):** Admin calls `release()`, receives SQD, migrates to RZLV via SQDMigration. If the beneficiary needs a new TemporaryHoldingV2, admin deploys one with RZLV via `TemporaryHoldingFactoryV2`.
- **Still locked:** Same fundamental problem as vesting - tokens can't be extracted early. The beneficiary continues using the old contract. After unlock, admin releases and migrates.

**Executable Fixes.** The `Executable` abstract contract is the base for both `SubsquidVesting` and `TemporaryHolding`. It has a reentrancy vulnerability:

```solidity
function execute(address to, bytes calldata data, uint256 requiredApprove) public returns (bytes memory) {
    // ...
    if (requiredApprove > 0) {
        SQD.approve(to, requiredApprove);           // 1. Approve before call
    }
    depositedIntoProtocol += SQD.balanceOf(address(this));  // 2. Record balance
    bytes memory result = to.functionCall(data);            // 3. EXTERNAL CALL (no lock!)
    uint256 balanceAfter = SQD.balanceOf(address(this));    // 4. Read balance after
    // ...
}
```

The external call at step 3 can re-enter `execute()` or any other function. Fix: add `ReentrancyGuardUpgradeable` with `nonReentrant` modifier. Also rename `SQD` to `token` and update the address check. (Defensive)

### Security Fixes Summary

**SafeERC20 Everywhere.** Multiple contracts call `transfer` and `transferFrom` without checking return values. RZLV (standard OZ ERC20) always returns true, so this is defense-in-depth. But it protects against future token changes and is best practice.

Affected contracts:
- `Staking.sol`
- `WorkerRegistration.sol`
- `RewardTreasury.sol`
- `GatewayRegistry.sol`

Pattern: `token.transfer(...)` → `token.safeTransfer(...)`.

**Executable Reentrancy Guard.** Affects all contracts inheriting from `Executable` (Vesting, TemporaryHolding).

**SubequalStrategy Duplicate Worker Bug.** Corrupts `workerCount` when duplicate worker IDs are passed.

### Gas Optimizations Summary

**WorkerRegistration Active Set Cleanup.** Three functions iterate the full `activeWorkerIds` set and filter inactive workers on every call. `RewardCalculation.effectiveTVL()` calls two of them, resulting in two full iterations. Fix: remove workers from `activeWorkerIds` when deregistration becomes effective, not only on withdrawal, and keep a separate track of deregistered-but-not-withdrawn workers. Active worker count is then derived from the cleaned active set.

**RewardCalculation Double Iteration.** `effectiveTVL()` calls both `getActiveWorkerCount()` and `getActiveWorkerIds()`, each iterating the full set. Fix: single call to `getActiveWorkerIds()`, derive count from `.length`. Additionally, `apyCap()` computes `effectiveTVL()` into a local variable `tvl` but then calls `effectiveTVL()` a second time in the return statement instead of reusing `tvl` - trivial fix, doubles the cost of every `apyCap()` call.

**DistributedRewardsDistribution Claim Optimization.** `claim()` calls `getOwnedWorkers()` which returns an unbounded array. Fix: add a bounded claim path that accepts worker IDs as a parameter and verifies ownership per ID, with matching treasury integration.

**Gateway Batch Bounds.** `register(bytes[], ...)` and `unregister(bytes[])` accept unbounded arrays. Fix: add a max batch size constant (e.g., 50). Revert if the array exceeds it.


---

## Phase 2.2 - Deployment and Parallel Launch

Once Phase 2.1 is complete, audited, and tested, we deploy the new system alongside the old one. The legacy network keeps running undisturbed on SQD. The new network starts fresh on RZLV.

```
OLD SYSTEM (SQD)                       NEW SYSTEM (RZLV)
Router ─── NetworkController           RouterV2 ─── NetworkControllerV2
       ─── Staking                              ─── StakingV2
       ─── WorkerRegistration                   ─── WorkerRegistrationV2
       ─── RewardTreasury                       ─── RewardTreasuryV2 (Phase 1)
       ─── RewardCalculation                    ─── RewardCalculationV2
       ─── DistributedRewardsDistribution        ─── DistributedRewardsDistributionV2
       ─── GatewayRegistry                      ─── GatewayRegistryV2
```

### Deployment Order

Strict dependency ordering. Each step depends on the previous:

1. **RZLV token** - already deployed after Phase 1.
2. **RouterV2 implementation + proxy** - deploy UUPS proxy and initialize immediately (temporary placeholders are acceptable) so admin is set and the proxy is never left uninitialized.
3. **NetworkControllerV2** - seed with current live parameters from old NetworkController.
4. **WorkerRegistrationV2** - initialize with RZLV + RouterV2.
5. **StakingV2** - initialize with RZLV + RouterV2.
6. **SoftCapV2 / LinearToSqrtCapV2** - initialize with RouterV2.
7. **RewardCalculationV2** - initialize with RouterV2 + SoftCapV2.
8. **DistributedRewardsDistributionV2** - initialize with RouterV2.
9. **RewardTreasuryV2** - Wire to RouterV2.
10. **RouterV2 final wiring** - set all contract references via `set*()` functions.
11. **GatewayRegistryV2** - deploy UUPS proxy, initialize with RZLV + RouterV2.
12. **EqualStrategyV2 / SubequalStrategyV2** - initialize with RouterV2 + GatewayRegistryV2.
13. **AllocationsViewerV2** - deploy with `GatewayRegistryV2` in constructor (no proxy).
14. **VestingFactoryV2** - initialize with RZLV + RouterV2.
15. **TemporaryHoldingFactoryV2** - initialize with RZLV + RouterV2.
16. **Optional bounded-claim wiring** - if enabled, wire bounded `claim`/`claimable` between `RewardTreasuryV2` and `DistributedRewardsDistributionV2`.

### Role Configuration

After deployment:

1. Grant `REWARDS_DISTRIBUTOR_ROLE` on `StakingV2` to `DistributedRewardsDistributionV2`.
2. Grant `REWARDS_TREASURY_ROLE` on `DistributedRewardsDistributionV2` to `RewardTreasuryV2`.
3. Whitelist `DistributedRewardsDistributionV2` on `RewardTreasuryV2`.
4. Set allowed vested targets on `NetworkControllerV2` for all new V2 contract addresses.
5. Set default strategy on `GatewayRegistryV2`.
6. **Bootstrap `DistributedRewardsDistributionV2` reward pipeline:** call `addDistributor()` for each distributor address, then set `setApprovesRequired()`, `setWindowSize()`, and `setRoundRobinBlocks()` to match desired quorum configuration. Without this step, `distributorIndex()` divides by zero and no reward commits can happen.
7. Grant `VESTING_CREATOR_ROLE` on `VestingFactoryV2` and `HOLDING_CREATOR_ROLE` on `TemporaryHoldingFactoryV2` to the operational admin.
8. Grant `PAUSER_ROLE` on all pausable V2 contracts to the designated pauser multisig.

### State Seeding

For a smoother transition, new contracts can optionally be seeded with state from the old ones:

- **Workers:** Admin script reads all active workers from old `WorkerRegistration`, calls a batch `seedWorkers()` function on `WorkerRegistrationV2`. Workers still need to post RZLV bond.
- **Network parameters:** Copy all params from `NetworkController` to `NetworkControllerV2`.
- **Gateway strategies:** Copy allowed strategies list.

Whether to seed or require full self-migration is an open question. Seeding is more user-friendly but adds deployment complexity and requires temporary admin-only batch functions.

### User Migration Flows

Both systems are live. Users migrate at their own pace.

**Worker Operators:**
```
1. Claim all pending rewards from old RewardTreasury
2. Deregister worker from old WorkerRegistration
3. Wait for lock period, withdraw SQD bond
4. Migrate SQD → RZLV via SQDMigration contract
5. Register worker on WorkerRegistrationV2 with RZLV bond
```


**Stakers (Delegators):**
```
1. Claim all pending rewards from old RewardTreasury
2. Withdraw stakes from old Staking contract (respecting lock period)
3. Migrate SQD → RZLV via SQDMigration contract
4. Deposit RZLV into StakingV2
```

**Gateway Operators:**
```
1. Unstake from old GatewayRegistry (respecting lock period)
2. Unregister gateways
3. Migrate SQD → RZLV
4. Register gateways on GatewayRegistryV2
5. Stake RZLV on GatewayRegistryV2
```

**Vesting Beneficiaries (Self-Migration):**
```
1. Legacy vesting contracts remain unchanged and continue their original release schedules
2. Beneficiary calls `release()` as SQD vests
3. Beneficiary migrates released SQD to RZLV via `SQDMigration`
4. Beneficiary stakes/deploys RZLV on the V2 network
5. Legacy vested targets are disabled only after confirming no required legacy exits remain for vesting/holding users
```

**Reward Claimers:**
```
1. Claim all pending rewards from old RewardTreasury (paid in SQD or RZLV, depending on when the Phase 1 reward switch happened)
2. If rewards received in SQD, migrate to RZLV
3. Future rewards claimed from RewardTreasuryV2 in RZLV
```


---

## Phase 2.3 - Sunsetting the Legacy Network

Once enough users have migrated to the new system, the legacy network transitions to a wind-down mode. Running two parallel systems indefinitely is not sustainable - this phase makes the shutdown explicit while keeping exit paths available.

### What Happens

1. **Announce deadline.** Communicate a clear cutoff date to all participants. Give enough runway for stragglers.
2. **Freeze new participation by parameters.** Keep old contracts unpaused, but block new activity operationally: set `Staking.maxDelegations = 0`, set `GatewayRegistry.maxGatewaysPerCluster = 0`, raise `GatewayRegistry.minStake` to near max uint, and raise `NetworkController.bondAmount` to the cap (< 1,000,000 SQD - hardcoded limit in the old contract). Note: `maxDelegations = 0` and `maxGatewaysPerCluster = 0` are absolute blocks. The `bondAmount` cap makes worker registration a strong economic deterrent but not mathematically absolute on the old system; `NetworkControllerV2` should raise or remove this cap to enable a hard freeze if needed.
3. **Keep exits open.** Existing users can still withdraw and claim rewards on legacy contracts.
4. **Migrate remaining SQD → RZLV.** Users who haven't migrated yet can still use the `SQDMigration` contract at any time.

### Migration Lifecycle

```
┌──────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│ Phase 2.2        │----->│ Phase 2.3            │----->│ Phase 2.4           │
│ Both Systems     │     │ Legacy Wind-Down     │     │ Legacy Retired      │
│ Active           │     │ (entries frozen)     │     │ (exits still open)  │
└──────────────────┘     └──────────────────────┘     └─────────────────────┘
```

---

## Phase 2.4 - Full Deprecation

The legacy network is operationally retired.

Legacy `WorkerRegistration`, `Staking`, and `GatewayRegistry` stay in passive-exit mode: new participation remains frozen by parameters, while self-service withdrawals/claims remain available for stragglers. Frontend/indexer support for legacy flows is discontinued.

The SQD Network is officially considered migrated. The only active system is the RZLV-based network running on the V2 contracts behind UUPS proxies.

The `SQDMigration` contract remains open indefinitely - anyone holding SQD can still exchange it for RZLV at 1:1. There's no reason to close this.

---

## Phase 2.5 - Post-Migration Feature Expansion

This is where the upgradeability investment pays off.

Because Phase 2.1 introduced UUPS proxies across all contracts, we no longer need to migrate state or tokens to add features. New functionality gets deployed as implementation upgrades - the proxy addresses stay the same, user positions stay intact, and the network doesn't skip a beat.

Throughout Phases 2.1–2.4, we continuously collect feedback from workers, stakers, and gateway operators about missing features, UX pain points, and protocol improvements. This feedback feeds directly into Phase 2.5.

### How Upgrades Work

```
                  ┌──────────────────────┐
                  │ UUPS Proxy (fixed)   │  ◄── Users interact with this address
                  │ address: 0xABC...    │
                  └──────────┬───────────┘
                             │ delegatecall
                  ┌──────────▼───────────┐
                  │ Implementation V2    │  ◄── Current logic
                  │ address: 0xDEF...    │
                  └──────────────────────┘
                             │ upgrade
                  ┌──────────▼───────────┐
                  │ Implementation V3    │  ◄── New logic, same proxy, same state
                  │ address: 0x123...    │
                  └──────────────────────┘
```

To add a feature to, say, `StakingV2`:

1. Develop and test `StakingV3` implementation.
2. Audit the delta.
3. Call `upgradeToAndCall()` on the proxy - the proxy now points to V3.
4. All existing stakes, delegations, and rewards carry over automatically.

No redeployment. No user migration. No token swaps.


The `__gap` arrays in every contract reserve storage slots for new state variables. As long as new variables are appended (not inserted), storage layout stays compatible.

---


## Open Questions

1. **Legacy vested-target shutdown timing.** At what exact point do we call `setAllowedVestedTarget(...)` on legacy `NetworkController` to block new legacy interactions from vesting/holding contracts while preserving any required legacy exits?
   - **Recommendation:** Keep legacy vested targets enabled through Phase 2.2 and most of Phase 2.3, then disable only after an explicit exit checklist is green: no remaining vesting/holding-controlled legacy stakes/workers/gateways that require protocol calls, plus a published final grace window.

2. **Transition period length.** How long do we run both systems in parallel (Phase 2.2) before sunsetting (Phase 2.3)?

3. **`DistributedRewardsDistribution` start block.** The new system needs a starting point for reward distribution. Do we set `lastBlockRewarded` to the deployment block, or to the last block rewarded in the old system?
   - **Recommendation:** Use a V2-local start point (activation/deployment boundary), not legacy `lastBlockRewarded`. Add an explicit init/start parameter (or operational first-commit rule) so first V2 distribution begins from the V2 activation block range only.
