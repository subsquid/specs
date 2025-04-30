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

## Results
