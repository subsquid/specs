# Portal config format

Each portal instance is passed a config file that specifies the datasets it should serve.

The config is a YAML file with the following structure:

```yaml
sqd_network:
  datasets: https://cdn.subsquid.io/sqd-network/datasets.yml
  serve: "all"  # only support "all" for now

datasets:
  "ethereum-mainnet":  # the "default name" of the dataset
    aliases: ["eth-main", "eth"]  # optional
    sqd_network:
      dataset_name: "ethereum-mainnet"
      # Or
      # dataset_id: "s3://ethereum-mainnet-2"  # explicitly specifies the dataset version, should rarely be used

  "arbitrum-one":
    aliases: ["arbitrum-mainnet", "arbitrum-main"]
    # If `sqd-network` is not specified, uses the network dataset with the same name (if any)

  "solana-mainnet":
    sqd_network:
      dataset_name: "solana-mainnet"
    real_time:
      kind: solana
      data_sources:
        - "https://..."
      retention:
        # If dataset is present in the network, the historical blocks will also be removed from hotblocks storage
        from_block: 250000000
        # Or
        # head: 2000
  
  "my-devnet":
    real_time:
      kind: evm
      data_sources:
        - "http://localhost:8000/hotblocks"
      retention:
        head: 100
    
  # The rest of the datasets are used from the mapping file

hotblocks:
  db: /data/hotblocks

hostname: http://0.0.0.0:8000  # used for building legacy API urls
```

All the fields with their default values may be found in the [source code](https://github.com/subsquid/sqd-portal/blob/master/src/config.rs)
