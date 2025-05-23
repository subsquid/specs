# DuckDB Extension, First Iteration, Timeline

## Intro

The trade-off between Trino (and similar solutions based on existing query engines) and the DuckDB approach was discussed by DK and TS on May, 06, 2025.
We decided to continue with the DuckDB approach. The main arguments in against Trino were:

* Java

* The additional resources Trino would force us to use to effeciently run a cluster 

* The limited control we would have concerning architecture and design decisions in general

* The learning opportunities we obtain by building the SQL engine based on smaller building blocks.

In this document, I discuss the effort needed to finish the first iteration of the DuckDB extension.

## Scope

The first iteration is defined by the followng diagram:

![DuckDB Prototype Architecture](attachments/duckdb-prototype.png?raw=true)

It consists of

* the DuckDB extension itself (following the Postgres extension)

* a simplified server providing 

  * metadata on querible entities

  * data from Parquet files based on the query plan sent from the extension.

The integration with the SQD portal and the workers is, thus, out-of-scope for this first iteration.
Instead a simplified server will be implemented. I propose, however, to clearly separate server and worker code from the get-go.
The code may run in the same process, but what workers do and what the portal does should be implemented in different crates.

Furthermore, the first iteration of the extension will be very simple. In particular, there will be no or very few code for more complex SQL tasks like joining, sorting and grouping.
The extension will receive data of individual streams, materialise them locally, and perform any additional tasks on local tables.
This will come with some inconvenience for users of the first iteration, forcing them, for example, to split a query into two parts, and it will, certainly, not be optimal in terms of performance. More iterations are needed to integrate everything smoothly and to optimise performance.

## Tasks

### Attach

My early experiments with DuckDB were based on table functions, which forces the user to provide SQL statements in the form

```
call sqd('select * from block where block_number between a and b');
```

The `attach` mechanism allows normal SQL usage in the DuckDB interface, _e.g._:

```
select * from sqd.solana.block where block_number between a and b;
```

Already in Tbilisi I started to implement the `attach` mechanism following the Postgres extension for DuckDB.
I interrupted this activity in order to look more deeply into the Trino query engine.
The remaining work will take about one week.

### Dev Environment

The dev environment encompasses the portal/worker-side of the prototype (the left box in the diagram).
The environment will be needed as long as these functions are not yet integrated with the SQD network.
I propose to further exploit the environment as testing platform and for future experiments.
It will be written in Rust and encompass the code that will be integrated with portal and worker.
I estimate the effort for the dev environment to about two weeks. However, some more query planning code will be necessary.
The development will, therefore, alternate between dev environment and query planning.

### Query Planning

On the long run, we will need **two** libraries for query planning, one in Rust and the other, for the DuckDB extension, in C++.
The library shall provide functionality to extract and remove parts of a query plan, to manipulate nodes and to insert new nodes into a plan.
Both flavours of the library will be mainly based on the `substrait` exchange format to avoid additional effort for working on other formats (such as DuckDB's own plan representation).
For the first iteration, only the foundations will be laid out.
The completion of this libray will be perfomed iteratively over many months according to the needs of milestones agreed in the future.
I estimate the effort necessary for the first iteration to at least one month.

### Testing

For the query engine we definitely need a good testing approach to guarantee that the engine does not change the meaning of the SQL statements passed in.
The dev environment is one important ingredient for such an approach.
Furthermore, I prose to use a [mock testing approach](https://en.wikipedia.org/wiki/Mock_object) to make tests easier to execute and to easily obtain deterministic verdicts.
The drawback of this approach is that it impacts code design.
External resources shall be implemented as `traits` which are implemented with production resources in production code and with mock objects in the test code.
A potential library to support mock testing, mitigating the impact on code design, may be [mockall](https://docs.rs/mockall/latest/mockall/) (which I haven't used much myself yet).
The additional effort for the test battery of the first iteration will be about two weeks.

## Timeline

The overall effort for the first iteration amounts to 9 weeks. For the timeline I consider additional tasks for myself including network tasks and additional research.

| Task      | Effort (h) | Finished | Milestone | Comment                     | Achieved |
|-----------|-----------:|----------|-----------| ----------------------------|----------|
| Attach    |         40 | 23/05/25 | M1        |                             | 23/05/25 |
| DevEnv    |         80 | 27/06/25 | M2        | iteratively with QueryPlan  |          |
| QueryPlan |        160 | 18/07/25 | M3        | iteratively with DevEnv     |          |
| Testing   |         80 | 31/07/25 | M4        | iteratively with all others |          |
| Overall   |        360 | 31/07/25 |           |                             |          |

### Milestones

#### M1

1. DuckDB extension queries data according to metadata

~2. DuckDB extension materialises data locally~
Comment: This cannot be M1 because we need data (coming from workers); therefore it is moved to M2.

#### M2

1. Server sends metadata to DuckDB extension

2. DuckDB extension uses the metadata from the server

3. Server sends queried data from Parquet files (M3.3 required)

4. DuckDB extension receives (and, if necessary, materialises) the data 

#### M3

1. DuckDB extension transforms DuckDb plan to substrait plan

2. DuckDB extension extracts subplan and sends it to the server

3. Server transforms substrait plan to Polars expressions and executes them over Parquet files 

#### M4

1. Test Battery exercises functionality of DuckDB extension

2. Test Battery exercises functionality of DuckDB extension and Server in tandem

3. Test Battery exercises
   
   * Projection (asterisk, field lists in various orders, aliases, constants, expressions, scalar functions)

   * Filter with complex conditions (and, or, not, between, in, parentheses, etc)
