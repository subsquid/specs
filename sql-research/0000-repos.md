# Repositories

## Server and Worker

[sql4sqd-prototype](https://github.com/subsquid/sql4sqd-prototype)

This repository contains the nucleus of the portal/worker-side code.
The query planning library was separated in its own repository.

Note that this repository is historical / documentary.

The latest code was migrated to
- sqd-portal
- worker-rs

## DuckDB

[duckdb-extension-prototype](https://github.com/subsquid/duckdb-extension-prototype)

Prototype for the client-side DuckDB extension (based on the Postgres extension). 

## Query Planner
[Query Planner](https://github.com/subsquid/qplan)

The above mentioned Query Planning Library.

## Netowrk Connector
[P2P Network Connector](https://github.com/subsquid/](https://github.com/subsquid/network_connector)

Connector to the Subsquid P2P library. 

## Trino

[trino-sqd](https://github.com/subsquid/trino-sqd)

Repository for Trino experiments based on a custom OpenAPI plugin for Trino.
Currently there is not much to see. I just manipulated the code to have a

* SQD catalog
* with a Solana schema
* with one table (node)
* and 3 rows in this table.

