# Assignment lifecycle

 ![](attachments/bcafd32c-7b4f-4e53-8b9d-7ff5b46ab980.png " =717x632")

## Publishing assignments

Once generated, a single file with assignments for all the Workers is published to a persistent storage under a unique content-addressable URL.
Another file under a well-known URL is updated to point to that assignment URL.

Example content of the `network-state.json`:
```json
{
  "network": "mainnet",
  "assignment": {
    "url": "https://metadata.sqd-datasets.io/assignment_mainnet_20241008T141245_242da92f7d6c.json.gz",
    "id": "20241008T141245_242da92f7d6c",
    "effectiveFrom": 1728385965
  }
}
```

The URL of the network state at this stage is provided with the Worker config.

The Workers check that file for updates every minute and if it points to a new assignment, download and start using it.

Portals also download this file to be able to parse [Pings](04_network_communication.md#pings) coming from Workers.

> Later, to switch to IPFS storage, the assignment may be published to the IPFS and it’s hash reference will be posted to a smart contract that is polled by the Workers.

> Note that if we replace the current Scheduler with this mechanism before migrating datasets to BitTorrent distribution, we should also take care of distributing Cloudflare signatures that allow fetching the datasets via HTTPS.

## Assignment format

The assignment is a JSON file with two sections.

* The list of all known chunks split by datasets. The chunks are enumerated in the order they follow in the assignments file.
* Individual assignments for the workers. Each assignment is represented by a delta-encoded array with indexes of the assigned chunks from the global chunk list.

With 2,000 workers and 500,000 assigned chunks the size of this file gzipped will be less than 20 MB.

If it grows too big, we can split it into a chunk list and assignments in different files.

### Why?

There is not much difference (5% uncompressed, 1.2% gzipped) between proto and JSON sizes, so JSON is chosen for simplicity and readability.

Chunk names and file urls have a lot of repetitions, so a compression gives good results and almost fully mitigates the necessity to avoid those repetitions manually by using string building patterns.

```none
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/balances.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/blocks.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/instructions.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/logs.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/rewards.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/token_balances.parquet
s3://solana-mainnet-1/0221000000/0221000000-0221000649-9QgFD/transactions.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/balances.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/blocks.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/instructions.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/logs.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/rewards.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/token_balances.parquet
s3://solana-mainnet-1/0221000000/0221000650-0221001299-Bfz4q/transactions.parquet
```

However, listing a single download URL per chunk and listing its files separately (instead of listing all individual full file URLs) saves about half of the compressed size. So the above list becomes:

```json
"chunks": [
  {
    "id": "0221000000/0221000000-0221000649-9QgFD",
    "baseUrl": "https://solana-mainnet-1.sqd-datasets.io/0221000000/0221000000-0221000649-9QgFD",
    "files": {
      "blocks.parquet": "blocks.parquet",
      "balances.parquet": "balances.parquet",
      "instructions.parquet": "instructions.parquet",
      "logs.parquet": "logs.parquet",
      "rewards.parquet": "rewards.parquet",
      "token_balances.parquet": "token_balances.parquet",
      "transactions.parquet": "transactions.parquet"
    },
    "sizeBytes": 210104850
  },
  {
    "id": "0221000000/0221000650-0221001299-Bfz4q",
    "url": "https://solana-mainnet-1.sqd-datasets.io/0221000000/0221000650-0221001299-Bfz4q",
    "files": {
      "blocks.parquet": "blocks.parquet",
      "balances.parquet": "balances.parquet",
      "instructions.parquet": "instructions.parquet",
      "logs.parquet": "logs.parquet",
      "rewards.parquet": "rewards.parquet",
      "token_balances.parquet": "token_balances.parquet",
      "transactions.parquet": "transactions.parquet"
    },
    "sizeBytes": 203580150
  }
]

```

The numbers in the comparison table are in millions of bytes.

| Chunks list format | Proto uncompressed | JSON uncompressed | Proto gzipped | JSON gzipped |
|----|----|----|----|----|
| Reuse all repeating strings | 25.5 | 21 | 5.7 | **5.8** |
| URL per chunk + filenames list per bucket | 66.5 | 70 | 7.7 | **7.8** |
| **URL and filenames list per chunk** | - | 150 | - | **8.2** |
| List all files’ urls | - | 383 | - | **19.4** |

## Encrypted Headers

In order to access the R2/S3 data source, workers have to present a number of HTTP headers. The scheduler creates these headers for workers and encodes them with PeerID-based encryption. As PeerID is basically an ed25519 public key, we use x25519 to generate an ephemeral key and Salsa to actually encrypt data. At the moment, identity is just provided alongside nonce and ciphertext, but we can use it to make the header's origin verifiable. As encryption deals in raw bytes, all new fields are base64-encoded. It is temporary measure until [p2p data sharing](03_data_delivery.md) is implemented.

Plaintext headers example:
```json
{"worker-id":"12D3KooWCFRfJMGNrYayrQbSn4h7Jy7dbC4uZTymrYqMZJLSexnq","worker-signature":"1730217695-G0vARZOxA1qQH3DmKnbhSm1dK8nAN9usmO1g83MbMdk%3D"}
```

## Example

Sample contents of `https://metadata.sqd-datasets.io/assignment_mainnet_20241008T141245_242da92f7d6c.json.gz`:

```json
{
  "datasets": [
    {
      "id": "czM6Ly9zb2xhbmEtbWFpbm5ldC0x",
      "baseUrl": "https://solana-mainnet-1.sqd-datasets.io",
      "chunks": [
        {
          "id": "0221000000/0221000000-0221000649-9QgFD",
          "baseUrl": "https://solana-mainnet-1.sqd-datasets.io/0221000000/0221000000-0221000649-9QgFD",
          "files": {
            "blocks.parquet": "blocks.parquet",
            "balances.parquet": "balances.parquet",
            "instructions.parquet": "instructions.parquet",
            "logs.parquet": "logs.parquet",
            "rewards.parquet": "rewards.parquet",
            "token_balances.parquet": "token_balances.parquet",
            "transactions.parquet": "transactions.parquet"
          },
          "sizeBytes": 210104850
        },
        {
          "id": "0221000000/0221000650-0221001299-Bfz4q",
          "baseUrl": "https://solana-mainnet-1.sqd-datasets.io/0221000000/0221000650-0221001299-Bfz4q",
          "files": {
            "blocks.parquet": "blocks.parquet",
            "balances.parquet": "balances.parquet",
            "instructions.parquet": "instructions.parquet",
            "logs.parquet": "logs.parquet",
            "rewards.parquet": "rewards.parquet",
            "token_balances.parquet": "https://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi.ipfs.dweb.link",
            "transactions.parquet": "transactions.parquet"
          },
          "sizeBytes": 203580150
        },
        ...
      ]
    }
  ],
  "workerAssignments": {
      "12D3KooWNZrHgTaFxm6nNxLxCySb8oTvmNnY9v3iAzFr4xnBs2bQ": {
          "status": "Ok",
          "chunksDeltas": [58,1,175,1,431,1,73,1,63,1,3,1],
          "encryptedHeaders": {
              "identity": "Y3WaDoknK44H/trvbxtlCH1EtdCXqb1jb0fIJZ6EWnA=",
              "nonce": "MQuTa4+7Dg9B0AfIg72YEuYJvRR69J+a",
              "ciphertext": "iKgjyIPEq1b052OyGQgPMRygleV2YzBOiYccq/ucE7eDTKNrmG7EtjYNqWz5AZuQ99F3tVpKOq/2Nf/dU2Yc7KobxnS9eD3fvxe5y0Ozt2UWyqXj5qHxfFlmKgRwA1hl7Zv9aqpkoUG7AjepIZP87bx04CQwvnYcaIhRI8wBR04qj6r736vy2URdTHH/b8FKB4314QmOZvr4VzixDCjg2Nusau02kKw="
          }
      },
      "12D3KooWQdFqTQjQPKfpXZtDdvVRrRvzmAAKSpCrwumS7Wji7eyD": {
          "status": "unreliable",
          "chunksDeltas": [46,1,27,1,257,1,165,1,307,1,11,1],
          "encryptedHeaders": {
              "identity": "Y3WaDoknK44H/trvbxtlCH1EtdCXqb1jb0fIJZ6EWnA=",
              "nonce": "MeiramDC7eqsVYdGocsD+t7jZv+oBGVN",
              "ciphertext": "4CzSVGtzPpyrpqsZRpOWQDwPScLmlQ8gCsb/Ee4j1/PGDb2KWRy8IBzG9rLlC0CL6bZYvr7DoSWoAF822w6xA1PNUJMATJk/rRf3p5mZydzCArlwMCOm4zYo0GHs1aFhXJ4eXl2eIeN92khkLzAEhDEh8mDuz/dEhi/ZH7REqUpR66FE89YS9pLWjuIw/wmMhgv+4r9ozOzMpRojla/CkKIrMxprbaVp/5D3"
          }
      }
  }
}
```
