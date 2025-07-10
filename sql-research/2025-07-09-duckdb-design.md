# SQL Engine and DuckDB Extension Design

## Intro

This document presents a report on what was achieved during the first iteration defined
in [DuckDB-Extension Roadmap](https://github.com/subsquid/specs/blob/main/sql-research/2025-05-12-duckdb-timeline.md).
The document discusses, in particular, the overall design of the **Squid Query Engine** (SQQED)
and the role and internal design of the DuckDB extension. During the discussion, I will mention pending tasks,
bugs and future improvements that I will then compile into a TODO list. The document concludes with a suggestion for a roadmap for further development
with the overall goal to have SQL core functionalities in production still in 2025.

## Overall Design

SQQED consists of five components:

* DuckDB

* The Squid Scanner (a DuckDB Extension)

* Plan (a query planning library written in Rust and to be integrated into SQD Network, SQD Portal and Worker)

* Portal components (metadata server and query planner)

* Worker components (query executor).

The following diagram shows the overall interaction of these components in processing a query (the metadata server is left out for simplicity):

<p align="center">
 <img src="attachments/sql-engine-2.png"
  alt="Squid Query Engine"
  width="65%"/>
</p>

The first important entity to note is the user in the top-left corner of the diagram. Without users that actually see an advantage in the engine for their work, there won't be an engine.
This sounds trivial - but I will actually come back to it. Some effort is, in fact, still needed to make the engine attractive for users in *different* use cases,
such as batch processing, currently the core functionality, but also for ad-hoc, explorative queries from the DuckDB CLI (or another interface).
The latter, I believe, is a strong argument for the use of SQL in general and, arguably, the first step of any data scientist looking at a new dataset.

The query is passed through the interface to DuckDB, which parses the SQL string and invokes the planner that transforms the query into a tree of tasks
consisting of sorting, grouping, projecting, filtering, joining and, at the leaves of the tree, table (or index) scanning.
When the DuckDB planner sees in the catalog that the scans relate to a SQD table, the Squid Scanner is invoked.
The scanner extracts the query plan, transforms it into another format (namely, *substrait*), serialises this format and sends it to the SQD Portal.
The portal responds with a set of subplans that are split per table and worker, each subplan associated with the URL of the worker.
The scanner, in turn, posts the subplans to the indicated workers and processes the result streams.
DuckDB's perspective, the only task that the scanner performs, is to somehow produce the data corresponding to the underlying entity denoted by SQD table,
and this is, indeed, how, for example, the Posgres Scanner for DuckDB works: the Postgres table appearing in DuckDB is just a table. What the scanner does
in this case is just to query this table in Posgres and to inject the Posgres data into DuckDB. The Squid Scanner is unique as it, additionally, has to coordinate the query.
SQD is not a single stand-alone database but a data lake. I will discuss the implications in the next section.

A scanner extension is basically a description of the work share between the standard DuckDB query engine and the external system. The following diagram illustrates that:

<p align="center">
 <img src="attachments/qplan-1.png"
  alt="A Query Plan"
  width="65%"/>
</p>

Most tasks, like grouping for example, are performed by the DuckDB query engine. The only task that is exclusively performed by the scanner extension is to produce data for the external data source. This, obviously, is inefficient for most case. The scanner would always produce all columns of all rows of the data source. The projection is therefore *pushed down* to the data source to reduce the columns, and filters, *i.e.* parts of the *where* condition, are pushed down to reduce the number of rows. For a data lake this essential, otherwise any query would produce billions of rows. Joins, likewise, act as implicit mutual filters for the tables involved and should be made explicit and then applied at the source.

The Squid Scanner sends the entire plan to the portal. The portal extract the relevant parts from the plan and creates subplans for individual workers according to the assignment of chunks. A query that involves several SQD tables would, hence, produce several subplans. In fact, since tables are split in chunks, even one table would produce more than one subplan, one such plan for each affected worker. The following diagram illustrates subplans derived from a DuckDB query plan: 

<p align="center">
 <img src="attachments/qplan-2.png"
  alt="SQD Sub-Plans"
  width="65%"/>
</p>

The subplans are sent back to the extension from where they are finally posted to workers. At the moment only projections are extracted from the plan. We still have to implement the filter pushdown. In the future joins should also be considered. The next section will discuss both aspects in more detail.

## DuckDB Extension

The DuckDB extension has two main parts: *catalog* management and the *scanner*. The first makes SQD metadata available to DuckDB as catalog interface, the second implements the query engine described in the previous sections.

### Catalog

DuckDB, like other relational databases, has a three-level data dictionary consisting of

* Catalog, the top level entry of a database's data dictionary;

* Schema, organising subsets in a catalog;

* Schema Entry, any database object like tables, types, views, stored procedures and so on within a schema.

The SQD extension implements the *attach* function that *attaches* an external resource to DuckDB. The function posts a request for metadata to the metadata server, part of the Portal. The pmetadata server answers with JSON document describing all available datasets as schemas including their entries. This is an example:

```json
{
    "name": "solana_mainnet",
    "tables": [
        {
            "name": "block",
            "schema": {
                "fields": [
                    {
                        "name": "number",
                        "type": "integer",
                        "nullable": false
                    },
                    {
                        "name": "hash",
                        "type": "varchar",
                        "nullable": false
                    },
                    ...
                ]
            },
            "partitionKey": [
               ...
            ],
            "chunks": [
               ...
            ],
            "stats": {
                "approx_num_rows": 1024
            }
        },
        ...
    }]
}
``` 

Currently, metadata are defined in a static file that is loaded by the portal (in fact: compiled into the code) and send as response to the metadata endpoint. In the future, a more dynamic approach will be needed to reflect frequently changing information like stats and chunks. Statistics are needed to report progress to DuckDB and, in the future, to implement more sophisticated optimisations.

Once the SQD network is attached, DuckDB makes all this information available through the normal catalog facilities, *e.g.*:

```sql
select * from information_schema.schemata where catalog_name = 'sqd';
```

| catalog_name | schema_name            | schema_owner | ... | 
|--------------|------------------------|--------------|-----|
| sqd          | etherum_sepolia_1      | duckdb       | ... |
| sqd          | hyperliquid_testnet_4  | duckdb       | ... |
| sqd          | solana_mainnet         | duckdb       | ... |

```sql
select * from information_schema.tables where table_catalog = 'sqd' and table_schema = 'solana_mainnet';
```

| table_catalog | table_schema   | table_name   | ... | 
|---------------|----------------|--------------|-----|
| sqd           | solana_mainnet | block        | ... |
| sqd           | solana_mainnet | transaction  | ... |
| ...           | ...            | ...          | ... |

```sql
desc sqd.solana_mainnet.block;
```

| column_name | column_type | ... | 
|-------------|-------------|-----|
| number      | INTEGER     | ... |
| hash        | VARCHAR     | ... |
| ...         | ...         | ... |

### Scanner

The scanner works in tandem with the DuckDB query engine. It is invoked for every attached resource used within a query which, for the SQD network, is always a table. The following diagram adds some more detail:

<p align="center">
 <img src="attachments/squid-scanner.png"
  alt="Squid Scanner"
  width="75%"/>
</p>

The main interface between DuckDB and the scanner is the scanner state. The internal design of this object is defined by the extension, the life cycle, however, is managed by DuckDB, which calls functions to create and initialise the state and to invoke the scanner with a state object. There is one such state per SQD table that appears in the query.

Just for illustration, the initialiser and the scanner have the following signatures:
```cpp
unique_ptr<GlobalTableFunctionState> SquidInitGlobalState(ClientContext &context, TableFunctionInitInput &input);
void SquidScan(ClientContext &context, TableFunctionInput &data, DataChunk &output) {
```

where `TableFunctionInput` contains the previously created `GlobalTableFunctionState` and `DataChunk` is the interface through which DuckDB receives the scanned data.

The first time the initialiser is invoked, the extension sets up the overall query state valid for all SQD scans in the scope of this specific query. During this initialisation, the extension is completely locked. No concurrent initialiser can overtake the first and set up an alternative truth. Once the query state is set, initialisers pass and pick up the resources that correspond to the table for which they are responsible. The query state contains (among others) the follow resources:

* Open connections to all workers

* Data that would enable a scanner to retry a connection in case of failure (URL and query plan)

* The projection: a list of columns, their types and positions in the output. 

During the initialisation process, the initialiser extracts the query plan from the DuckDB `client context`, transforms and serialises it and sends it to the portal. The response, as already discussed above, consists of the subplans for all tables, which are then posted to the workers resulting.

One qualification concerning the current state: the portal does not send, in fact, query plans but rather SQL strings. The reason for that is merely pragmatic. The `C++` substrait library which is used as a starting point is very immature. Already now it poses restrictions on the SQL functionality we can support. Before extending the use of this library, namely for incoming substrait plans, I want to make sure that it is complete and sufficiently robust. That, however, is a two-weeks effort.

### Implementation Details
- curl
- substrait (here: missing SQL features)
- json, sql and arrow
- worker + chunks
- retries
- multi-threaded scans

### Make it Efficient
- Portal extracts relevant blocks to filter out chunks!
- Worker handling local filters
- Filter pushdown in extension
- Apply limits, aggregates and filters when we have only one table (no joins)
- Research idea: sqd_functions, e.g. sqd_limit(...), sqd_count(...) that handle certain tasks on worker side
- Note timestamp!

## Roadmap

| Task                  | Where? | Effort (h) | Finished | Milestone | Owner | Comment                     | Achieved |
|-----------------------|--------|-----------:|----------|-----------|-------|-----------------------------|----------|
| Code Improvement      | X      |            | 31/07/25 | M-1       | TS    |                             |          |
| Filter pushdown       | X+P+W  |            | 15/08/25 | M-2       | TS    |                             |          |
| Worker integration    | W      |            | 15/08/25 | M-3       | DK    |                             |          |
| Arrow not JSON        | X+W    |            | 31/08/25 | M-4       | TS    |                             |          |
| SQL completion        | X      |            | 15/09/25 | M-5       | TS    |                             |          |
| Substrait not SQL     | X+P    |            | 30/09/25 | M-6       | TS    |                             |          |
| Portal integration    | P      |            | 30/09/25 | M-7       | DK    |                             |          |
| More testing          | X+P+W  |            | 15/10/25 | M-8       | TS    |                             |          |
| Retry                 | X      |            | 30/10/25 | M-9       | TS    |                             |          |
| Multi-threaded Scan   | X      |            | 30/10/25 | M-10      | TS    |                             |          |
| Minor optimisations   | X+P+W  |            | 15/11/25 | M-11      | TS    |                             |          |
| Special functions     | X+P+W  |            | 30/11/25 | M-12      | TS    |                             |          |
| Experimental roll-out | X+P+W  |            | 15/12/25 | M-13      | DK    |                             |          |
| Stats                 | X+P+W  |            | N/A      | N/A       | N/A   |                             |          |
| Local joins           | X+P+W  |            | N/A      | N/A       | N/A   |                             |          |
| Overall               |        |            | 31/12/25 |           |       |                             |          |

### Milestones
