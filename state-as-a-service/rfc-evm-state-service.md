# RFC: EVM State-as-a-Service

**Authors**: SQD Labs  
**Status**: Draft  
**Created**: February 2026  
**Target**: Internal review → PoC greenlight

---

## Abstract

We propose building a **stateless EVM execution platform** — a system that decouples blockchain state storage from smart contract execution. A centralized, read-optimized database holds the full EVM state for any supported chain, while client-side tooling executes smart contract view functions locally by pulling only the required state slices on demand.

This architecture makes read-side EVM execution **infinitely horizontally scalable**: compute is offloaded to clients, the state database serves only raw key-value lookups, and the Subsquid Network's existing block and transaction pipeline feeds the state population layer.

The initial PoC targets **Polygon PoS** with latest-state-only, a single-machine deployment, and a working demo that replaces `eth_call` RPC for reading Uniswap v3 pool state.

---

## 1. Problem

### 1.1 The RPC Bottleneck

Every dApp, indexer, analytics tool, and wallet that needs to read on-chain state does so through `eth_call` — a JSON-RPC method that asks a full node to execute a smart contract function and return the result. This model has fundamental scaling problems.

**Server-side execution doesn't scale.** Every `eth_call` consumes CPU on the node. Node operators rate-limit aggressively: Alchemy caps free tiers at 330 compute units/second; Infura at 10 requests/second. Paid tiers cost $49–$999+/month and still impose limits. For indexers scanning thousands of contracts across millions of blocks, these limits are the primary throughput bottleneck.

**Archive access is expensive.** Reading state at historical block heights requires an archive node — 2–12 TB of storage depending on the chain, costing $500–$2,000/month to operate. Most RPC providers charge premium rates for archive access.

**Bulk reads are pathological.** Common indexing patterns — "read the price of 500 Uniswap pools at every block for the last month" — require millions of sequential RPC calls. There is no bulk read API. Each call is an independent HTTP request with full EVM execution on the server.

### 1.2 What Subsquid Already Solves

The Subsquid Network provides high-throughput bulk access to blocks, transactions, logs, and traces across 100+ EVM chains. For event-driven indexing (reading `Transfer` logs, `Swap` events, etc.), SQD eliminates the RPC bottleneck entirely.

But a significant class of on-chain data **cannot be accessed via events** — it can only be read by calling smart contract view functions. Examples include Uniswap v3 tick data and concentrated liquidity positions, Aave/Compound interest rate model parameters and health factors, on-chain governance proposal states and voting power, ENS resolution and reverse lookups, token metadata (`name()`, `symbol()`, `decimals()`), and complex DeFi positions requiring multi-contract reads.

Today, SQD users who need this data must fall back to RPC calls, re-introducing the exact bottleneck the network was designed to eliminate.

### 1.3 The Opportunity

If we can serve EVM state directly — the raw storage slots, account balances, and contract bytecode — then clients can execute view functions locally without any server-side computation. This turns the scaling model inside out: the server's job shrinks to serving key-value lookups (cheap, cacheable, horizontally scalable), while the client does the EVM execution (cheap, parallelizable, zero marginal cost to us).

---

## 2. Market Fit & Strategic Advantage

### 2.1 Why SQD Is Uniquely Positioned

**We already have the data.** The Subsquid Network stores complete block and transaction histories for 100+ chains. This is the exact input needed to derive EVM state at any block height. No other state-serving solution starts with this advantage — competitors would need to sync archive nodes from scratch for each chain.

**We already have the distribution.** Thousands of indexer developers use the SQD SDK today. The state service slots into existing workflows as a new data source alongside logs and transactions. The client SDK can share the same developer experience, configuration, and billing.

**We already handle multi-chain.** Supporting 10 EVM chains via RPC requires 10 archive node deployments. Our state population pipeline is a single revm-based replayer parameterized by chain config — adding a new chain is a configuration change, not an infrastructure project.

### 2.2 Competitive Landscape

| Solution | Model | Limitations |
|---|---|---|
| **Alchemy / Infura / QuickNode** | Server-side `eth_call` | Rate-limited, expensive at scale, per-call pricing |
| **Self-hosted archive nodes** | Full node operation | $500–$2K/month per chain, operational burden |
| **Reth / Erigon (local)** | Local flat state DB | Single-machine, not a service, requires full sync |
| **Helios (light client)** | Client-side + consensus proofs | Latest state only, requires consensus participation |
| **Axiom** | ZK-proven historical state | High latency (proof generation), limited to specific queries |
| **SQD State Service** | Client-side execution + remote state | No rate limits, infinite compute scaling, bulk-read native |

The key differentiator: every other solution either executes server-side (doesn't scale) or requires the client to participate in consensus (complex, latest-only). We occupy a new point in the design space — **trusted state service with optional client-side verification**.

### 2.3 Target Users

**Primary**: SQD indexer developers who currently mix SQD event data with RPC calls for state reads. The state service eliminates the RPC dependency entirely, completing the SQD data story.

**Secondary**: Analytics platforms (Dune, Nansen-style), DeFi dashboards, and portfolio trackers that need bulk historical state reads. These users currently pay thousands per month in RPC costs.

**Tertiary**: Wallet and dApp developers who want faster, cheaper `eth_call` equivalents for their frontends.

---

## 3. Feasibility Assessment

### 3.1 Why This Is Tractable Now

**revm is production-grade.** The Rust EVM implementation used by Reth, Foundry, and Arbiter provides a complete, tested, embeddable EVM. It compiles to WASM for browser execution and supports custom `Database` trait implementations — exactly the hook we need for remote state fetching. We use one dependency for state population (server-side replay) and client-side execution.

**Flat state storage is a solved problem.** Reth and Erigon proved that you don't need the Merkle Patricia Trie for execution — only for consensus proofs. Flat key-value state (address → account, (address, slot) → value) is 10–100x faster for random reads. We adopt this pattern directly.

**View functions are small.** A typical `view` or `pure` function touches 5–50 storage slots. Even complex DeFi reads (Uniswap v3 pool state, Aave health factors) access fewer than 200 slots. The data transfer per call is measured in kilobytes, not megabytes. This makes the remote-fetch model practical even over high-latency connections.

**EVM is deterministic.** Given identical state and calldata, execution produces identical results on every EVM chain. One engine, parameterized by chain config, serves all chains. Polygon, Base, Arbitrum, BSC — the only differences are hardfork schedules and a handful of custom precompiles.

### 3.2 Hard Problems & How We Handle Them

**State size at scale.** Ethereum mainnet has approximately 1.2 billion accounts and 8 billion storage slots at head. Full historical state with deltas reaches multi-TB even with compression. Mitigation: start with latest-state-only (tens of GB per chain), add historical in phases, use delta encoding for versioned storage.

**Storage slot discovery.** Before executing a view function, the client doesn't know which slots will be accessed. This is the core architectural challenge. Our solution: the server performs a speculative execution, records the access list, and ships the full state slice to the client in a single round trip. The client can optionally re-execute locally for verification. Details in Section 5.4.

**State population speed.** Full replay of Ethereum from genesis takes weeks. For the PoC, we bootstrap from an existing state snapshot and replay only recent blocks. For production, we pipeline replay across block ranges in parallel. SQD's bulk data access makes this significantly faster than replaying via RPC.

**Chain-specific quirks.** Polygon's Bor consensus injects state sync transactions not present in the standard transaction list. Arbitrum adds ArbOS precompiles. These require per-chain handling but are well-documented and finite in scope. revm supports custom precompile injection.

---

## 4. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  CLIENT                                                                      │
│                                                                              │
│  ┌──────────┐    ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │ User App │───▶│ @sqd/evm-state   │───▶│ revm (WASM or native)       │   │
│  │ (JS/Rust)│    │ TypeScript SDK    │    │ executes view functions     │   │
│  └──────────┘    └────────┬─────────┘    └──────────────────────────────┘   │
│                           │                              ▲                   │
│                           │  fetch state slices           │ SLOAD callbacks  │
│                           ▼                              │                   │
│                    ┌──────────────┐                       │                   │
│                    │ Local Cache  │───────────────────────┘                   │
│                    │ (LRU slots)  │                                           │
│                    └──────┬───────┘                                           │
└───────────────────────────┼──────────────────────────────────────────────────┘
                            │ WebSocket / HTTP
                            ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  STATE SERVING LAYER                                                         │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  State Query API (axum — HTTP + WebSocket)                             │  │
│  │                                                                        │  │
│  │  GET  /v1/storage/:chain/:addr/:slot   → 32-byte value                │  │
│  │  GET  /v1/account/:chain/:addr         → {nonce, balance, code_hash}  │  │
│  │  GET  /v1/code/:chain/:addr            → bytecode                     │  │
│  │  POST /v1/batch                        → multi-slot fetch             │  │
│  │  POST /v1/prefetch                     → speculative exec + state     │  │
│  │  WS   /v1/stream                       → interactive slot fetch       │  │
│  └────────────────────────────┬───────────────────────────────────────────┘  │
│                               │                                              │
│  ┌────────────────────────────▼───────────────────────────────────────────┐  │
│  │  Versioned State Database (libmdbx / RocksDB)                          │  │
│  │                                                                        │  │
│  │  Storage table:  key = [addr:20B][slot:32B]       → value:32B         │  │
│  │  Account table:  key = [addr:20B]                 → {nonce,bal,hash}  │  │
│  │  Code table:     key = [code_hash:32B]            → bytecode          │  │
│  │  Meta table:     key = "head_block"               → block_number      │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                            ▲
                            │ populated by
                            │
┌──────────────────────────────────────────────────────────────────────────────┐
│  STATE POPULATION PIPELINE                                                   │
│                                                                              │
│  ┌───────────────┐   ┌────────────────┐   ┌────────────────────────────┐   │
│  │  Subsquid      │──▶│  Block / Tx    │──▶│  revm-based Replayer       │   │
│  │  Network       │   │  Decoder       │   │  (executes all txs,        │   │
│  │  (data lake)   │   │  (alloy types) │   │   captures state diffs)    │   │
│  └───────────────┘   └────────────────┘   └────────────┬───────────────┘   │
│                                                         │                    │
│                                              state diffs per block           │
│                                                         ▼                    │
│                                                ┌────────────────┐           │
│                                                │  Batch Writer   │           │
│                                                │  → DB           │           │
│                                                └────────────────┘           │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Design Details

### 5.1 State Database

For a latest-state-only deployment, the database is a set of flat KV tables with no temporal indexing. This is dramatically simpler than a full versioned store.

**Engine choice**: libmdbx for the PoC (memory-mapped, sub-microsecond reads, proven in Reth), with a migration path to RocksDB for production (better concurrent write throughput, more tuning knobs).

**Schema**:

```
Table: storage
  Key:   [address:20 bytes][slot:32 bytes]   (52 bytes, fixed)
  Value: [value:32 bytes]

Table: accounts
  Key:   [address:20 bytes]                  (20 bytes, fixed)
  Value: [nonce:8][balance:32][code_hash:32]  (72 bytes, fixed)

Table: code
  Key:   [code_hash:32 bytes]
  Value: [bytecode:variable]

Table: metadata
  Key:   "head_block"
  Value: [block_number:8 bytes]
```

**Size estimate for Polygon latest state**:

| Data | Count | Key+Value Size | Total |
|---|---|---|---|
| Accounts | ~150M | 92 bytes | ~14 GB |
| Storage slots | ~500M | 84 bytes | ~42 GB |
| Contract code | ~2M unique | ~10 KB avg | ~20 GB |
| **Total (uncompressed)** | | | **~76 GB** |
| **Total (with compression)** | | | **~25–40 GB** |

This fits comfortably on a single machine with 64 GB RAM and a 500 GB NVMe drive.

### 5.2 State Population Pipeline

The replayer is a Rust binary that reads blocks and transactions from the Subsquid Network, executes them with revm against the current state, and writes the resulting state diffs to the database.

```rust
// Core replay loop (simplified)
fn process_block(&mut self, block: Block) -> Result<()> {
    let mut evm = Evm::builder()
        .with_db(&self.db)
        .with_block_env(block_env_from(&block))
        .with_spec_id(spec_for_block(block.number, &self.chain_spec))
        .build();

    for tx in block.transactions {
        evm.tx_mut().caller = tx.from;
        evm.tx_mut().transact_to = tx.to;
        evm.tx_mut().data = tx.input;
        evm.tx_mut().value = tx.value;
        // ... gas, nonce, etc.

        let result = evm.transact_commit()?;
        // State diffs are accumulated in the CacheDB layer
    }

    // Flush dirty state to persistent storage
    self.db.commit(block.number)?;
    Ok(())
}
```

**Bootstrapping strategy**: Rather than replaying Polygon from genesis (~200M+ blocks), we import a recent state snapshot (Erigon publishes these as torrents) and replay only the delta from the snapshot block to head. This reduces initial sync from weeks to hours.

**Polygon-specific handling**: Bor consensus injects state sync transactions (bridge deposits from Ethereum L1) that are not in the standard transaction list. The pipeline must either source these from SQD's chain-specific fields or supplement them via Bor RPC (`bor_getAuthor`). This is a known, bounded problem.

### 5.3 State Serving API

A Rust HTTP + WebSocket server built with axum. The API is intentionally minimal — it serves raw state, not computed results.

**HTTP endpoints** handle one-shot and batch reads. The batch endpoint is critical for performance: a single `POST /v1/batch` with 50 slot reads is dramatically faster than 50 individual `GET` requests.

**The WebSocket endpoint** (`/v1/stream`) supports interactive slot fetching during client-side EVM execution. The client opens a persistent connection, and each `SLOAD` during execution triggers a small message exchange. Typical view functions complete in 5–20 round trips over a single connection.

### 5.4 Client-Side Execution & Slot Discovery

The central architectural question: when the client wants to execute `contract.slot0()`, it doesn't know in advance which storage slots the function will read. We solve this with a **prefetch** model.

```
Client                                   State Server
  │                                           │
  │  1. POST /v1/prefetch                     │
  │     { to, calldata, chain }               │
  │──────────────────────────────────────────▶│
  │                                           │
  │     Server executes speculatively,        │
  │     records all accessed slots.           │
  │                                           │
  │  2. Response: {                           │
  │       result: "0x...",                    │
  │       accessList: {                       │
  │         accounts: [...],                  │
  │         storageKeys: { addr: [slot,...] } │
  │       },                                  │
  │       stateSlice: {                       │
  │         "addr:slot": "value", ...         │
  │       }                                   │
  │     }                                     │
  │◀──────────────────────────────────────────│
  │                                           │
  │  3. Client re-executes locally with       │
  │     pre-loaded state (optional verify)    │
  └───────────────────────────────────────────┘
```

**Single round trip.** The server does one EVM execution (fast — it has local state), records every `SLOAD`, `BALANCE`, and `EXTCODEHASH`, then returns the result alongside the full state slice needed to reproduce it. The client can verify by re-executing locally in WASM, or simply trust the result.

This hybrid approach captures the best of both models: the server handles the hard part (slot discovery) cheaply since it has local state, and the client retains the option to verify. For indexer workloads where millions of calls are made, the server's speculative execution results can be cached and reused across clients.

**For the PoC**, the prefetch endpoint is the primary execution path. Interactive WebSocket fetch exists as a fallback and for advanced users who want fully trustless client-side execution.

### 5.5 Client SDK

The SDK ships as an npm package (`@sqd/evm-state`) with a TypeScript wrapper around a WASM-compiled revm core. It provides three levels of abstraction.

**Low-level**: raw `call(to, calldata)` returning hex bytes.

**ABI-aware**: `client.contract(address, abi).read.functionName(args)` with automatic encoding and decoding via alloy/viem types.

**Drop-in replacement**: a viem-compatible custom transport, so existing code using `publicClient.readContract()` works with zero changes.

```typescript
// Drop-in replacement for viem
import { createPublicClient, custom } from 'viem';
import { polygon } from 'viem/chains';
import { EvmStateClient } from '@sqd/evm-state';

const sqd = new EvmStateClient({ endpoint: 'wss://state.sqd.dev/polygon' });

const client = createPublicClient({
  chain: polygon,
  transport: sqd.asViemTransport(),
});

// Existing code works unchanged — no RPC calls made
const slot0 = await client.readContract({
  address: poolAddress,
  abi: uniswapV3PoolAbi,
  functionName: 'slot0',
});
```

### 5.6 Multi-Chain Support

The EVM is deterministic and the state model is identical across all EVM chains. The replayer is parameterized by a `ChainSpec` that encodes hardfork schedules and custom precompiles. Adding a new chain requires the chain configuration, a Subsquid Network data source for that chain, and any chain-specific precompile implementations.

| Chain | State Size (est.) | Special Handling |
|---|---|---|
| Ethereum | ~40 GB (latest, compressed) | Baseline — no special handling |
| Polygon PoS | ~25–40 GB | Bor state sync transactions, state receiver precompile |
| Base / Optimism | ~10–20 GB | OP Stack L1 fee precompile, L1Block contract |
| Arbitrum | ~15–25 GB | ArbOS precompiles (0x64–0x6E), Stylus contracts (future) |
| BSC | ~30–40 GB | Parlia consensus, comparable state size to Ethereum |
| Monad | ~5–10 GB (new chain) | Standard EVM, parallel execution transparent to state model |
| MegaETH | ~5–10 GB | Very high block rate — pipeline must sustain high write throughput |

---

## 6. PoC Plan

### 6.1 Scope

| Parameter | Decision |
|---|---|
| Chains | Polygon PoS only |
| State | Latest only (no historical block queries) |
| Reorgs | Ignored — assume finalized blocks |
| Infrastructure | Single machine (64 GB RAM, 1 TB NVMe) |
| Demo | Drop-in `eth_call` replacement for Uniswap v3 pool reads |

### 6.2 Implementation Timeline

**Sprint 1 — State DB + Population (Weeks 1–2)**

Days 1–2: Rust workspace setup. Crates: `revm`, `libmdbx-rs`, `alloy`. Define DB schema, implement read/write operations, unit tests for storage and account CRUD.

Days 3–4: SQD data fetcher. Stream blocks + transactions for Polygon from the Subsquid Network. Deserialize into alloy types. Validate against known block hashes.

Days 5–6: Replayer implementation. Configure revm with Polygon chain spec (chain ID 137, hardfork schedule, Bor precompiles). Execute transactions, collect state diffs, write to DB. Handle system transactions.

Days 7–8: Bootstrap from snapshot. Import a recent Polygon state snapshot (Erigon torrent or equivalent). Run the replayer from the snapshot block to chain head.

Days 9–10: Validation. Spot-check 1,000 random `(address, slot)` pairs against a Polygon archive RPC. All values must match. Binary search any discrepancies to the diverging block.

**Deliverable**: A libmdbx instance with Polygon latest state, updating live from SQD.

**Sprint 2 — State API (Week 3)**

Days 1–2: HTTP API with axum. Endpoints: `/v1/storage/:addr/:slot`, `/v1/account/:addr`, `/v1/code/:addr`, `/v1/batch`, `/v1/head`. JSON responses with hex-encoded values.

Day 3: WebSocket endpoint `/v1/stream` for interactive slot fetch. Implement the message protocol: `sload`, `account`, `code`, `sload_batch`.

Day 4: Prefetch endpoint `/v1/prefetch`. Server-side speculative execution with revm, return result + access list + state slice.

Day 5: Load testing. Benchmark random reads (target: >50K point reads/sec on NVMe). Profile, tune libmdbx cache, add connection pooling.

**Deliverable**: Running API serving Polygon state at `http://localhost:8080`.

**Sprint 3 — Client SDK (Weeks 4–5)**

Days 1–3: Rust client library. `RemoteDB` implementing revm's `Database` trait with HTTP + WebSocket transports and an LRU slot cache. Unit tests against the live API.

Days 4–5: WASM compilation with `wasm-pack`. Test in Node.js. Optimize binary size with `wasm-opt -Oz` and `wee_alloc`. Target: under 3 MB gzipped.

Days 6–7: TypeScript wrapper. `EvmStateClient` class, ABI-aware `.contract()` method, viem-compatible custom transport adapter. Published as `@sqd/evm-state`.

Day 8: Integration tests. Round-trip: JS SDK → WASM → WebSocket → API → DB → response. Verify against RPC results.

**Deliverable**: Working npm package that executes Polygon view functions against the state API.

**Sprint 4 — Demo + Benchmarks (Week 6)**

Days 1–2: DEX demo. Uniswap v3 WMATIC/USDC pool reader: `slot0()` for price, `liquidity()`, full tick map scan across the active range. Show the viem drop-in replacement working with existing DeFi code.

Day 3: Benchmark script. Compare SQD state service vs. Polygon RPC (Alchemy, QuickNode) for single calls (latency), 100 parallel pool reads (throughput), and full tick map scan of 200+ ticks (bulk read).

Day 4: Documentation. README, architecture diagram, usage examples, known limitations.

Day 5: Demo recording. Tag `v0.1.0`.

**Deliverable**: Working end-to-end demo with published benchmarks.

### 6.3 Tech Stack

| Component | Technology |
|---|---|
| EVM engine | `revm` 19.x (Rust) |
| State database | libmdbx via `libmdbx-rs` |
| State population | revm replayer on SQD block/tx stream |
| Serving API | `axum` 0.8 (HTTP + WS) |
| Client core | Rust → WASM via `wasm-pack` |
| Client wrapper | TypeScript, viem-compatible |
| ABI encoding | `alloy-sol-types` 0.8 |
| Serialization | `serde` + `serde_json` |

### 6.4 PoC Success Criteria

| Metric | Target |
|---|---|
| **Correctness** | 100% match on 1,000 random `eth_call` results vs. Polygon archive RPC |
| **Single-call latency** | < 50ms end-to-end from client SDK (local network) |
| **Throughput** | > 1,000 view function calls/sec from a single client |
| **Bulk read** | 200-tick Uniswap v3 scan < 1 second (vs. 30+ seconds via RPC) |
| **State freshness** | Database within 30 seconds of chain head |
| **Demo** | Working viem drop-in replacement for `readContract` |

### 6.5 PoC Risks & Mitigations

| Risk | Severity | Mitigation | Fallback |
|---|---|---|---|
| Polygon state sync txs missing from SQD data | High | Check SQD data schema for Bor-specific fields immediately in Sprint 1 | Supplement via `bor_getAuthor` RPC; for PoC, manually patch affected accounts |
| State mismatch after replay | High | Validation script comparing 1,000 random slots against archive RPC; run after every full sync | Binary search diverging block, compare tx-by-tx |
| revm WASM binary too large (>10 MB) | Medium | `wasm-opt -Oz`, strip debug symbols, `wee_alloc` allocator | Ship native binary for Node.js; WASM only for browser |
| libmdbx write lock blocks reads during population | Medium | Separate reader/writer processes with `MDBX_NORDAHEAD` | Switch to RocksDB (native concurrent read/write) |
| Prefetch latency too high | Low | Measure server-side execution time; should be <5ms for typical view functions | Cache prefetch results for popular contracts |

---

## 7. Post-PoC: Road to Production MVP

### Phase 1 — Multi-Chain + Historical State (Weeks 7–12)

**Goal**: Support 3–5 chains with versioned state queryable at any block height.

**7.1 Versioned State Database**

Replace the latest-state-only schema with a temporal key encoding that supports point-in-time queries.

```
Key: [address:20B][slot:32B][inverted_block_height:8B]
     where inverted_block_height = MAX_UINT64 - block_height

A prefix seek on (address, slot) returns the most recent value first.
"State at block N" = seek to the first key where inverted_block_height >= (MAX - N).
```

This is the same pattern used by Erigon and Reth. Only changed slots are written per block, so the storage overhead is proportional to state churn, not total state size.

Migrate from libmdbx to **RocksDB** at this stage. RocksDB's column families allow separating hot (recent 1,000 blocks) from cold (deep history) data with different compaction and compression strategies. Bloom filters eliminate disk reads for missing keys.

**Storage estimate for full Ethereum history**:

| Component | Size |
|---|---|
| Latest state snapshot | ~40 GB |
| Historical state diffs (~20M blocks) | ~3–8 TB |
| Contract bytecode | ~20 GB |
| **Total (compressed with zstd)** | **~2–5 TB** |

L2 chains are 10–50x smaller. Polygon full history fits in ~200–500 GB.

**7.2 Additional Chain Deployments**

Add Base, Arbitrum, and BSC. Per-chain work includes chain spec configuration (hardfork schedule, chain ID), custom precompile implementations (OP Stack L1 fee for Base, ArbOS for Arbitrum), state snapshot import + replay pipeline, and validation against each chain's archive RPC.

Target: 2–3 weeks per chain with the pipeline already built.

**7.3 Parallel Replay Pipeline**

Partition the block range into segments and replay in parallel across multiple cores or machines. Each segment produces state diffs that are merged into the database. This reduces full-chain replay from weeks to days.

```
Blocks 0–1M:     Worker 1 → diffs → DB
Blocks 1M–2M:    Worker 2 → diffs → DB
Blocks 2M–3M:    Worker 3 → diffs → DB
...
```

Requires a merge step to resolve cross-segment dependencies (contracts deployed in segment 1 whose state is modified in segment 2). The simplest approach: replay segments sequentially but parallelize transaction execution within each segment.

**Phase 1 Deliverable**: 3–5 chains with full historical state, queryable at any block height via the API.

---

### Phase 2 — Production Infrastructure (Weeks 13–18)

**Goal**: Horizontal scaling, high availability, and production-grade operational tooling.

**7.4 Read Replica Architecture**

The state database is read-heavy by orders of magnitude. Deploy multiple read replicas behind a load balancer, with a single writer that processes new blocks and replicates diffs to readers.

```
                     ┌──────────────┐
                     │ Load Balancer│
                     └──────┬───────┘
                ┌───────────┼───────────┐
                ▼           ▼           ▼
         ┌──────────┐ ┌──────────┐ ┌──────────┐
         │ Reader 1 │ │ Reader 2 │ │ Reader 3 │
         │ (RocksDB │ │ (RocksDB │ │ (RocksDB │
         │  replica)│ │  replica)│ │  replica)│
         └──────────┘ └──────────┘ └──────────┘
                            ▲
                            │ WAL replication
                     ┌──────────────┐
                     │    Writer    │
                     │ (replayer +  │
                     │  primary DB) │
                     └──────────────┘
```

**7.5 Reorg Handling**

For production, we must handle chain reorganizations. When a reorg is detected (new block at an already-processed height), the pipeline rolls back state diffs for the orphaned blocks and replays the new canonical chain. With the versioned key scheme, rollback is a bounded delete operation: remove all entries where `block_height > reorg_point`.

For latest-state-only (PoC), this is trivial — just re-apply from the fork point. For versioned state, we need a WAL (write-ahead log) of applied diffs so they can be reversed.

**7.6 Caching Layer**

Add a Redis or in-memory cache tier between the API and the database. Cache popular slots (top 100 DeFi contracts account for the majority of reads) and prefetch results. Cache invalidation is block-driven: when a new block is processed, invalidate all slots that changed.

**7.7 Monitoring + Observability**

Prometheus metrics for read/write latency (p50, p95, p99), request throughput by endpoint, state freshness (seconds behind chain head), cache hit rate, DB size per chain, and reorg frequency and rollback time.

Grafana dashboards. PagerDuty alerts for state lag >60 seconds or correctness check failures.

**Phase 2 Deliverable**: Production deployment serving multiple chains with HA, reorg handling, and operational monitoring.

---

### Phase 3 — Advanced Features (Weeks 19–26)

**Goal**: Differentiated features that expand the addressable market beyond basic `eth_call` replacement.

**7.8 State Diffing API**

```
GET /v1/diff/:chain/:address?from=N&to=M
→ All storage slot changes for the contract between blocks N and M
```

This is extremely valuable for indexers. Instead of scanning events and making RPC calls to understand state transitions, users get a direct feed of "what changed and when." No other service offers this at scale.

**7.9 Merkle Proof Generation**

For users who need trustless verification (bridges, light clients, ZK applications), generate Merkle proofs on demand from the flat state. The proof confirms that a given `(address, slot) → value` mapping is consistent with the state root at a specific block.

This can be done lazily: maintain the flat state for fast reads, and build proof paths only when requested. The trie structure can be computed from the flat state without storing the full trie.

**7.10 Real-Time State Streaming**

WebSocket subscription for state changes:

```
SUBSCRIBE /v1/subscribe/:chain/:address
→ Stream of { slot, oldValue, newValue, blockNumber } as new blocks are processed
```

Enables reactive indexing: instead of polling, applications receive state changes in real-time as the pipeline processes blocks.

**7.11 Speculative Execution Cache**

For the top N contracts per chain, pre-execute common view functions at every new block and cache the results. Serve these directly from cache without any execution — the fastest possible response. Cache key: `(chain, contract, function_selector, calldata_hash, block_number)`.

This turns the most common reads into simple key-value lookups with sub-millisecond latency.

**Phase 3 Deliverable**: State diffing, Merkle proofs, real-time streaming, and speculative caching as additional API features.

---

## 8. Full Timeline Summary

| Phase | Weeks | Scope | Milestone |
|---|---|---|---|
| **PoC** | 1–6 | Polygon latest state, single machine, DEX demo | Working demo, published benchmarks |
| **Phase 1** | 7–12 | Multi-chain (3–5), historical state, versioned DB | Historical queries across chains |
| **Phase 2** | 13–18 | HA infrastructure, reorgs, caching, monitoring | Production deployment |
| **Phase 3** | 19–26 | Diffing API, Merkle proofs, streaming, spec cache | Full feature set, public launch |

**Total time to production MVP (Phases 1–2)**: ~18 weeks / 4.5 months with a team of 2–3 engineers.

**Total time to full product (through Phase 3)**: ~26 weeks / 6.5 months.

---

## 9. Limitations & Open Questions

### Known Limitations

**Read-only.** This system serves view function execution only. It cannot submit transactions, estimate gas for writes, or simulate state-modifying calls (though the latter could be added with an ephemeral state layer).

**Trust model.** Without Merkle proofs (Phase 3), clients trust the state database. This is acceptable for indexing and analytics workloads but not for security-critical applications like bridges or ZK provers. The prefetch model allows optional client-side verification, which provides a middle ground.

**Not a full RPC replacement.** Methods like `eth_getTransactionReceipt`, `eth_getLogs`, `eth_getBlockByNumber`, and write operations are not supported. This is a state query service, not a general-purpose node. It is complementary to existing RPC providers, not a replacement for all use cases.

**WASM performance.** revm compiled to WASM runs approximately 3–5x slower than native. This is still fast enough for typical view functions (under 10ms), but complex functions with heavy computation may be noticeably slower in browser contexts. The native Rust client has no such limitation.

**State freshness.** There is an inherent pipeline delay between a block being produced and its state being available in the database. The target is under 30 seconds, but this means the service is not suitable for latency-critical applications that need the absolute latest state (e.g., MEV searchers).

### Open Questions

**Pricing model.** Per-read pricing (like RPC providers)? Per-GB storage? Flat subscription? The client-side execution model means our compute costs are near zero — the primary cost is storage and bandwidth. This enables pricing that is dramatically cheaper than RPC.

**SQD Network integration.** Should state serving be a new worker type in the Subsquid Network? Or a centralized service operated by SQD Labs? The P2P distribution model would improve decentralization and fault tolerance, but adds significant complexity.

**Verkle tree readiness.** Ethereum's planned migration from Merkle Patricia Tries to Verkle trees will make proofs much smaller (~150 bytes vs. ~3 KB). This significantly improves the economics of trustless client-side verification. Should we design the proof system for Verkle from the start, or build Merkle proofs first and migrate later?

---

## 10. Conclusion

The EVM State-as-a-Service architecture is feasible, strategically aligned with SQD's existing data infrastructure, and addresses a real gap in the market. The core insight — that read-side EVM execution can be decomposed into cheap state lookups plus client-side computation — enables a scaling model that no existing RPC provider can match.

The PoC is scoped to be achievable in 6 weeks with minimal infrastructure risk. The path from PoC to production MVP is well-defined and builds incrementally on proven technologies. The Subsquid Network's existing multi-chain data pipeline provides a significant competitive advantage in state population speed and chain coverage.

We recommend proceeding with the PoC targeting Polygon, with a DEX state reader as the initial demo, and evaluating Phase 1 expansion after benchmarking results are in.
