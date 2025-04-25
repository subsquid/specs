# SQL for SQD Network

Our immediate goal is to make the data and compute power of SQD Network accessible for well-established 
analytical SQL engines, such as DuckDB, ClickHouse, Apache Spark, etc.

Concretely, we aim to teach SQD Network workers to execute a certain set of relational operators, namely:

* Scan
* Filter
* Projection with rich set of scalar expressions and blockchain specific data decoding functions. 

For each SQL engine, a powerful plugin should be developed, 
that would 

* expose SQD Network data tables and UDFs to engine users
* analyze and rewrite engine plans to push as much work to SQD as possible.

## Architecture

![Architecture](attachments/duckdb-arch.png?raw=true)

We have:

* A set of SQD Network workers
* Portal - client software, that manages interaction with SQD Network
* Client - any query engine, that wishes to utilize SQD Network.

Such interaction scheme:

* Aligns with [Arrow Flight RPC framework](https://arrow.apache.org/docs/format/Flight.html)
* Does not route large amounts of traffic through a single location
* Extends to serving arbitrary queries.

## Decentralization specifics

All computations, performed by network workers

* Should be reproducible
* Should have bounded and controlled computational complexity
* Should have clear cost formula derived only from input and output.

## First step prototype

![First step prototype](attachments/duckdb-prototype.png?raw=true)

As a first step, let's try to develop [DuckDB](https://duckdb.org) plugin, 
that would allow to query parquet files served by a simplistic gRPC service.

The gRPC service should be able to

1. Accept [substrait query plan](https://substrait.io)
2. Validate and compile it to [polars lazy DataFrame](https://pola.rs)
3. Return query results as gRPC stream of [record batches](https://arrow.apache.org/docs/format/Columnar.html#recordbatch-message)

Simple column selection and filtering should be supported.
