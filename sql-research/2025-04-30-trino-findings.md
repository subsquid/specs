# Trino Findings

## Intro

This document summarises my findings on Trino after some experiments.
For more background on Trino and a generic trade-off, please refer to [Trino for SQD](2025-04-18-trino-sqd-outlook.md).

## Goal

My goal with the Trino experiments was to understand difficulty and effort involved with developing a SQD plugin for Trino.
This is related, on the one hand, to the interfaces provided by Trino and, on the other, to the tasks we would need to implement, namely

* The Metadata server, including pushdowns

* The Split Manager that breaks down tables to chunks

* The code for our workers that produce and filter data at the source

* The RecordSetProvider that relays the data from the source to Trino for further processing.

It was not my goal to implement all these components or to investigate in detail what needs to be implemented.

## What Was Done?

I copied the code of an existing custom plugin, namely the [OpenAPI plugin](https://github.com/nineinchnick/trino-openapi/), that is designed to provide data through an HTTP API
with an OpenAPI spec serving as metadata. This plugin is simple enough to serve as basis for some experiements and resembles, to some extent, our tasks. 

I mainpulated the code

* to provide metadata independent of the OpenAPI Spec used by the original plugin

* to provide data related to those metadata.

Trino organises metadata in catalogs which are provides by plugins. Each catalogs contains one or more schemas which, in turn, contain tables, _eg._:

```
trino> show catalogs;
  Catalog  
-----------
 myexample 
 sqd       
 system    
 tpch      
(4 rows)

trino> show schemas from sqd;
       Schema       
--------------------
 information_schema 
 solana             
(2 rows)

trino> show tables from sqd.solana;
 Table 
-------
 block 
(1 row)
```

The catalog is available with the plugin. Schemas are made available through an interface listing the schemas:

``` 
public static final String SCHEMA_NAME = "solana"; // it's just harcoded
@Override
public List<String> listSchemaNames(ConnectorSession connectorSession)
{
    return List.of(SCHEMA_NAME);
}
``` 

The contents of the schema is defined as a simple map `tablename` &#8594; `column list`:

``` 
public SqdSchema() {
    this.tables = Map.of(
        "block", Arrays.asList(
            SqdColumn.builder()
                .setName("number")
                .setType(INTEGER)
                .setIsNullable(false)
                .build(),
            SqdColumn.builder()
                .setName("hash")
                .setType(VARCHAR)
                .setIsNullable(false)
                .build(),
            SqdColumn.builder()
                .setName("parent_number")
                .setType(INTEGER)
                .setIsNullable(true)
                .build(),
            ...
    );
}
```
With this code the table metadata are available:

```
trino> desc sqd.solana.block;
    Column     |  Type   | Extra | Comment 
---------------+---------+-------+---------
 number        | integer |       |         
 hash          | varchar |       |         
 parent_number | integer |       |         
 parent_hash   | varchar |       |         
 height        | integer |       |         
(5 rows)
```

Obviously, the metadata can be simply generated from a document sent from a remote server (and that is actually what the OpenAPI plugin does).

The table data are made available through the RecordSetProvider interface overriding `getRecordSet`. The structure of a record is just a list of types and a list of lists, each sublist defining one row:

```
Type[] ts = new Type[] {INTEGER, VARCHAR, INTEGER, VARCHAR, INTEGER};

List<List<?>> rows = new ArrayList();

List<Object> one = new ArrayList();
List<Object> two = new ArrayList();
List<Object> three = new ArrayList();

one.add(Integer.valueOf(1));
one.add(String.valueOf("deadbeef"));
one.add(null);
one.add(null);
...

two.add(Integer.valueOf(2));
...

three.add(Integer.valueOf(3));
...

rows.add(one);
rows.add(two);
rows.add(three);

return new InMemoryRecordSet(Arrays.asList(ts), rows);
``` 

These data are queryable:

```
trino> select * from sqd.solana.block;
 number |   hash   | parent_number | parent_hash | height 
--------+----------+---------------+-------------+--------
      1 | deadbeef |          NULL | NULL        |      3 
      2 | ba5eba11 |             1 | deadbeef    |      4 
      3 | f005ba11 |             2 | ba5eba11    |      5 
(3 rows)
```

The data would be generated through an RPC interface to one of our workers and then converted into the format expected by Trino.

## Results
The code shown above implements the main interfaces Trino requires from the plugin. Two more interfaces need to be implemented:

* The pushdown mechanism (implemented as part of the Metadata interface, that accepts or rejects pushdowns for filtering, projection, sorting and so on)

* The `SplitManager` that breaks down a table into its partitions, _ie._, to chunks.

