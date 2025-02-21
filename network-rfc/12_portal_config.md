# Portal config format (DRAFT)

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
        first_block: 250000000
        # Or
        # from_head: 2000
  
  "my-devnet":
    real_time:
      kind: evm
      data_sources:
        - "http://localhost:8000/hotblocks"
      retention:
        from_head: 100
    
  # The rest of the datasets are used from the mapping file

hotblocks_db_path: /data/hotblocks
hostname: http://0.0.0.0:8000  # used for building legacy API urls
```

### A tricky case

Suppose, someone had the following config:
```yaml
datasets:
  "ethereum-mainnet":
    sqd_network:
      dataset_name: "ethereum-mainnet"  # maps to "s3://ethereum-mainnet-1" right now
    real_time:
      # ...
  "ethereum-mainnet-beta":
    sqd_network:
      dataset_id: "s3://ethereum-mainnet-2"
```

Then, at some point, we change the mapping so that `ethereum-mainnet` starts pointing to `s3://ethereum-mainnet-2`.
Now both config entries point to the same dataset.
We can't allow that because, for example, it becomes ambiguous which dataset to track for hotblocks retention.

The possible options to handle this:
- Never hot-switch the mapping, but instead signal the portal admin to update the config and restart.
- If some network dataset matches multiple entries from the config, prefer the entry with the "default name" equal to the dataset name in the mapping. In case above, the `ethereum-mainnet-beta` dataset will be disabled (breaking the clients that use it).
- Allow multiple config entries (and hence hotblock databases) to point to the same network dataset. It will complicate the hotblocks cleanup process, but is probably the most user-friendly option.
