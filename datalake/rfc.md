# RFC: Community-Driven Blockchain Data Lake

**Date**: 2025-01-16  
**Version**: 1.0 (Draft)  
**Authors**: [Your Name], [Team Members], & Community Contributors

---

## Table of Contents
1. [Overview](#1-overview)  
2. [Scope & Goals](#2-scope--goals)  
3. [High-Level Architecture](#3-high-level-architecture)  
4. [Data Submission & Governance](#4-data-submission--governance)  
5. [Metadata Format](#5-metadata-format)  
6. [Catalog (Directory) Service](#6-catalog-directory-service)  
7. [Data Layout & Conventions](#7-data-layout--conventions)  
8. [Real-Time vs. Historical Data Flow](#8-real-time-vs-historical-data-flow)  
9. [AI Agent Usage Scenarios](#9-ai-agent-usage-scenarios)  
10. [Security & Access Control](#10-security--access-control)  
11. [Implementation Plan](#11-implementation-plan)  
12. [Open Questions & Next Steps](#12-open-questions--next-steps)

---

## 1. Overview
This document specifies the design for a **community-driven data lake** containing **blockchain data** (e.g., DeFi events, token trades, NFT transfers, wallet balances). The goals are:

- **Ease of Contribution**: Community members can publish datasets without complex infrastructure.  
- **Discoverability**: A central *catalog service* helps AI agents or human users find relevant datasets.  
- **Lightweight Querying**: No heavy clusters (Spark, Trino, etc.) required—users or agents can directly query Parquet files on object storage (e.g., Cloudflare R2 or AWS S3), plus optional real-time feeds.  
- **Append-Only Model**: Blockchain data is inherently append-only, simplifying ingestion and versioning.

---

## 2. Scope & Goals

### 2.1 In-Scope
1. **Append-Only Storage**  
   - Storing Parquet files with minimal partitioning.  
   - “Historical” data sets that grow over time.

2. **Lightweight Metadata Standard**  
   - JSON-based schema for describing each dataset.  
   - Core fields: name, owner, schema, license, etc.

3. **Catalog/Directory Service**  
   - An API or repository for dataset discovery.  
   - Basic search (by dataset name, tags, chain, etc.).

4. **Community Contribution Workflow**  
   - Guidelines for how contributors submit new datasets or updates.  
   - Automated validation of metadata (CI pipelines, etc.).

5. **Basic Real-Time Integration**  
   - Optional local or “script-based” indexing for near-live data.  
   - Minimal overhead, no large streaming cluster.

### 2.2 Out of Scope
1. **Full Transactional Lakehouse**  
   - E.g., Iceberg, Delta Lake with ACID transactions.

2. **Advanced Security/Entitlements**  
   - Row-level or column-level security.

3. **Sophisticated Catalog Features**  
   - Complex lineage, data masking, cross-dataset joins via a single interface.

4. **Large ETL Platforms**  
   - Airflow, Spark streaming, etc.

---

## 3. High-Level Architecture

```
                ┌─────────────────────────┐
                │  Catalog/Directory API  │
                │   (stores dataset meta) │
                └───────────┬─────────────┘
                            │
  ┌─────────────────────────▼───────────────────────────┐
  │                   Object Storage                    │
  │ ┌───────────────────────┬─────────────────────────┐ │
  │ │ Datasets Contributed  │                         │ │
  │ │ (Parquet Files)       │  Partitioned by chain,  │ │
  │ │ & Metadata            │  date, etc.             │ │
  │ └───────────────────────┴─────────────────────────┘ │
  └──────────────────────────────────────────────────────┘
                            │
     ┌──────────────────────▼───────────────────────────┐
     │ Consumer Tools & AI Agents                       │
     │  - DuckDB or Postgres FDW reading Parquet        │
     │  - Real-time "local" DB for fresh data           │
     └───────────────────────────────────────────────────┘
```

1. **Object Storage**: The main repository of historical blockchain datasets (Parquet).  
2. **Catalog Service**: Stores & indexes metadata describing each dataset (name, schema, object path, etc.).  
3. **Community Contributions**: Users submit new datasets or updates via a workflow (e.g., GitHub PR or REST API).  
4. **Query**: AI agents or devs use DuckDB/Postgres FDW to read data *directly* from the object store.  
5. **Real-Time**: Optional small pipeline that writes near-live data to a local DB, also queryable from the same environment.

---

## 4. Data Submission & Governance

### 4.1 Submission Workflow
1. **Contributor Creates Metadata**  
   - Follows the standard JSON schema (see [Section 5](#5-metadata-format)).

2. **Contributor Publishes Data to Object Storage**  
   - Places Parquet files in an agreed sub-path, e.g. `r2://community-lake/dex_swaps/chain=.../date=...` or `s3://community-lake/...`.

3. **Registration**  
   - Contributor either:  
     - **Option A**: Submits a Pull Request to a GitHub repository that stores the metadata, or  
     - **Option B**: Calls a `POST /datasets` endpoint on the Catalog Service with the metadata JSON.

4. **Review & Validation**  
   - Automated checks ensure required fields are present and no naming conflicts arise.  
   - Maintainers approve or reject with feedback.

5. **Catalog Entry Created/Updated**  
   - The dataset is now discoverable via `GET /datasets`.

### 4.2 Community Governance
- **Versioning**: Datasets can increment versions if schema changes.  
- **Owner & Maintainers**: The original submitter plus optional co-maintainers.  
- **Open Review**: The community can comment or submit issues if data is incomplete/incorrect.

---

## 5. Metadata Format
We propose a **JSON-based** structure heavily inspired by **Frictionless Data’s JSON Table Schema** or a custom schema. **Key fields**:

```json
{
  "name": "dex_swaps",
  "title": "DEX Swaps (Ethereum, BSC)",
  "description": "Community-contributed dataset of all DEX swap events.",
  "owner": "0x123abc",
  "license": "CC-BY-4.0",
  "version": "2025-01-16",
  "keywords": ["defi", "swap", "ethereum", "bsc"],
  "resources": [
    {
      "path": "r2://community-lake/dex_swaps/",
      "schema": {
        "fields": [
          {
            "name": "tx_hash",
            "type": "string"
          },
          {
            "name": "chain",
            "type": "string"
          },
          {
            "name": "timestamp",
            "type": "datetime"
          },
          {
            "name": "token_in",
            "type": "string"
          },
          {
            "name": "amount_in",
            "type": "decimal"
          }
        ],
        "primaryKey": ["tx_hash"]
      },
      "partitions": ["chain", "date"],
      "update_frequency": "daily"
    }
  ]
}
```

1. **`name`**: Unique slug for the dataset.  
2. **`title`/`description`**: Human-friendly.  
3. **`owner`**: On-chain address or user identity.  
4. **`license`**: E.g., CC-BY, MIT, etc.  
5. **`keywords`**: For search.  
6. **`resources`**: Each resource points to a data “path” plus a schema describing fields.  

**Validation**:
- A small tool or CI check ensures required fields exist and schema fields match known data types.

---

## 6. Catalog (Directory) Service

### 6.1 Functionality
- **CRUD for Metadata**:
  - `POST /datasets` – register a new dataset  
  - `GET /datasets` – list/search datasets  
  - `GET /datasets/{name}` – fetch details for a specific dataset  
  - `PUT /datasets/{name}` – update dataset metadata (e.g., new version)

- **Search**:
  - Filter by keywords, chain, date, or partial name match.

### 6.2 Implementation Options
1. **Lightweight DB + REST**  
   - A small Postgres or SQLite plus a Node/Flask/FastAPI service.  
   - Easiest to implement, well-known patterns.

2. **GitHub-Based**  
   - All metadata in a central repository.  
   - A static site or simple service reads from the repo and provides a JSON/GraphQL endpoint for search.

**Recommendation**: Start with a simple REST API service (Option 1). We can evolve to more advanced catalogs if needed.

---

## 7. Data Layout & Conventions

1. **Object Storage Bucket/Namespace Structure**  
   - `r2://community-lake/{dataset_name}/[partition_key1=value1]/...[file.parquet]`  
   - Example: `r2://community-lake/dex_swaps/chain=ethereum/date=2025-01-01/part-000.parquet`

2. **Partitions**  
   - Typically by `chain`, `date`, or `block_range`.  
   - Contributors should define them in their metadata’s `partitions` array.

3. **File Format**  
   - **Parquet** recommended for columnar analytics.  
   - CSV/JSON allowed but discouraged for large datasets.

---

## 8. Real-Time vs. Historical Data Flow

### 8.1 Historical (Append-Only)
- **Daily or Hourly** Parquet snapshots appended to object storage.  
- Typically derived from blockchain event logs or subgraphs.  
- Minimal overhead, easy to query with DuckDB.

### 8.2 Real-Time (Optional)
- **Local Script/Repo**: The contributor might maintain a small “listener” script for near-live data that writes to a local DB (DuckDB or Postgres).  
- The metadata could point to instructions or a Git repo link.  
- **User** or **AI agent** can clone and run it if they need real-time data.

---

## 9. AI Agent Usage Scenarios

1. **Agent Receives a Query**  
   - E.g. “Fetch total volume of ETH->USDC swaps in the last 24h.”

2. **Agent Calls Catalog**  
   - Finds the `dex_swaps` dataset, sees the storage path and schema.

3. **Agent Launches DuckDB**  
   - `SELECT * FROM parquet_scan('r2://community-lake/dex_swaps/chain=ethereum/*.parquet') WHERE date >= current_date - 1;`

4. **Agent Provides Answer**  
   - Minimizes hallucinations thanks to explicit schema in metadata.

---

## 10. Security & Access Control

1. **Public Read**  
   - By default, all datasets are publicly readable if they have an open license.  
   - Bucket/namespace policy: `GetObject` allowed for everyone.

2. **Write Permissions**  
   - Only owners or verified contributors can upload new data to their dataset path.  
   - Catalog service requires auth (API key, OAuth, etc.) to register or update datasets.

3. **Optional Private Datasets**  
   - Could be done with restricted ACLs or separate private bucket.  
   - Not a primary focus for the initial launch.

---

## 11. Implementation Plan

### 11.1 Phase 1: MVP
1. **Repo Setup**  
   - Create a GitHub repo: `community-blockchain-datalake`  
   - Define the minimal JSON metadata schema and add examples.

2. **Catalog Service**  
   - Simple Node.js/FastAPI service + Postgres DB.  
   - Endpoints: `GET /datasets`, `GET /datasets/{id}`, `POST /datasets`, etc.

3. **Object Storage Configuration**  
   - `community-lake` (public read), with partitions for initial bootstrapped data.

4. **Bootstrap Datasets**  
   - Add 2–3 example datasets (e.g., `dex_swaps`, `nft_transfers`, `token_prices`) to seed the lake.  
   - Provide sample queries in the repo’s README.

5. **CI Validation**  
   - A small script checks new metadata JSON for required fields upon PR or `POST /datasets`.

6. **Documentation**  
   - Outline how contributors can create metadata, upload data, and register in the catalog.

### 11.2 Phase 2: Enhancements
1. **Web UI**  
   - A simple front-end for browsing datasets (optional but user-friendly).

2. **Search & Filters**  
   - Expand catalog queries (e.g., filter by chain, tags).

3. **Real-Time Integration Examples**  
   - Provide reference code for a local listener that writes live data to a DuckDB table.

4. **Advanced Metadata**  
   - Stats (row counts, min/max block number), versioning.

5. **Community Governance Features**  
   - Upvotes, star ratings, or “verified data” badges.

---

## 12. Open Questions & Next Steps

1. **What Should the Baseline Metadata Fields Be?**  
   - Finalize required vs. optional fields in the JSON schema.

2. **Submission Workflow**  
   - Decide between a purely GitHub-based flow vs. the REST API (or both).

3. **Licensing Model**  
   - Confirm the default license (e.g., CC0, CC-BY) for contributed data.

4. **Object Storage Costs & Funding**  
   - Who pays for storage if community contributions grow large?

5. **Support for Non-EVM Chains**  
   - Should the partitions always assume EVM-based addresses, or do we want to handle Solana, Aptos, etc.?

---

# Conclusion
This RFC defines a **community-driven** blockchain data lake architecture with a **metadata-driven catalog service** at its core. By adopting a **simple JSON format**, **append-only object storage (Parquet)**, and a **lightweight submission workflow**, we can rapidly onboard community datasets. AI agents and human analysts alike will benefit from consistent, discoverable data—without heavy infrastructure.

**Action**:  
- Please review and provide feedback.  
- Once finalized, the development team can begin Phase 1 implementation immediately.

**Contact**:  
- [Your Name / Team] – _Slack/GitHub handle_  
- [Project Repo or Issue Tracker Link] – for ongoing collaboration and discussion.
