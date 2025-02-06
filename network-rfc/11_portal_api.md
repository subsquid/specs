# Portal API

The portal exposes the HTTP API with the following methods

#### `GET /status`

Responds with a JSON with human-readable information about the portal's state. The exact format may change.

Response example:
```json
{
  "peer_id": "12D3KooWDJwsMFBEUxSUMxTKaBXLMvnn7pr9zsP73PMQrb9kPrtL",
  "status": "registered",
  "operator": "0xd1c2…11fa",
  "current_epoch": {
    "number": 19619,
    "started_at": "2025-02-04T10:40:35+00:00",
    "ended_at": "2025-02-04T11:00:47+00:00",
    "duration_seconds": 1212
  },
  "sqd_locked": "100000",
  "cu_per_epoch": "100000",
  "workers": {
    "active_count": 1645,
    "rate_limit_per_worker": "0.04950495049504951"
  },
  "portal_version": "0.5.5"
}
```

#### `GET /datasets`

Lists the existing datasets as a JSON array. See [`/metadata` endpoint](#get-datasetsdatasetmetadata) for the field description.

Response example:
```json
[
  {
    "dataset": "ethereum-mainnet",
    "aliases": ["eth-mainnet"],
    "real_time": false
  },
  {
    "dataset": "solana-mainnet",
    "aliases": [],
    "start_block": 250000000,
    "real_time": true
  },
]
```

#### `GET /datasets/<dataset>/metadata`

Responds with the information describing the dataset. Notably, contains the `real_time` field, indicating whether the portal supports the real-time mode for this dataset.

Response example:
```json
{
  "dataset": "ethereum-mainnet",
  "aliases": ["eth-main"],
  "start_block": 0,
  "real_time": false
}
```

#### `GET /datasets/<dataset>/state`

Responds with a summary of stored blocks ranges for the given dataset. May be used for displaying status in the UI.\
TBD

#### `POST /datasets/<dataset>/finalized-stream`

Starts streaming data for the given query passed in the request body. See [Streaming API](#streaming-api).

#### `GET /datasets/<dataset>/finalized-stream/height`

Responds with a single decimal number — the highest number of the block available to be served by the `/finalized-stream` endpoint.\
Note that the first available block is not always 0.

#### `POST /datasets/<dataset>/stream`

Same as [`/finalized-stream`](#post-datasetsdatasetfinalized-stream) but with the [real-time mode](#real-time-mode) support.

#### `POST /datasets/<dataset>/stream/height`

Responds with a single decimal number — the highest number of the block available to be served by the `/stream` endpoint.\
Note that the first available block is not always 0.

### Deprecated endpoints

These endpoints are preserved for compatibility with the old clients and should not be used.

#### `GET /datasets/<dataset>/height`

Same as `/datasets/<dataset>/finalized-stream/height`

#### `GET /datasets/<dataset>/<start_block>/worker`

Gets the worker url for querying the dataset starting from the given block.

#### `GET /datasets/<base64_id>/query/<worker_id>`

Sends the query to the worker. The query is passed in the request body.

## Streaming API

The following applies to the [`/finalized-stream`](#post-datasetsdatasetfinalized-stream) and [`/stream`](#post-datasetsdatasetstream) endpoints.

### Request

The request body is a JSON query following the [SQD query format](https://docs.sqd.ai/subsquid-network/reference/evm-api/).

The client **should** pass the following request headers:
- `Content-Type: application/json`

The client **may** pass the following request headers:
- `Accept-Encoding`: one of `gzip` or `deflate`. If omitted, the response will be decompressed by the nginx making streaming less efficient. Once implemented, the `deflate` option should be preferred to avoid decompression.

### Response

The response is a stream of JSON objects in [JSON Lines](https://jsonlines.org/) format, each representing a block. The response may be empty (with `204` status code) indicating that no blocks are available for the given range yet.

Upon receiving the request, the portal starts streaming the blocks from `fromBlock` in the order of increasing block numbers. The portal may return any number of blocks before terminating the stream. Due to the streaming nature of the HTTP protocol, it's not possible to communicate the reason of termination to the client. Whenever a successful non-empty response has been received, the client should check the last returned block number and send a follow-up request if more blocks are needed.

Aside from the blocks explicitly requested by the query, the response always contains the first and the last block of the scanned range. It may also contain additional blocks not requested by the client.

If a block `N` was included in the response, it is guaranteed that all the existing blocks on the simple path (in terms of block chain) from the `fromBlock` (from the query) to `N` matching the query are also included in the response.

### Status codes

| Reason | HTTP Code | Details |
|-|-|-|
| Internal error (crash) during request handling | `500` | The request should not be retried because it may be causing the error |
| The data chunk exists, but no worker is ready to serve it | `503` | The request should be retried later |
| All the workers rate limited this portal | `429` | Should be retried after the specified delay |
| The query is invalid | `400` | The request should not be retried |
| The dataset is not found | `404` | The client should only request datasets from the list returned by `/datasets` |
| Invalid endpoint | `404` | |
| The `fromBlock` is above the last known block | `204` | Those blocks may be present later. It's up to the client to decide how often to check for updates. |
| The requested block range falls into the dataset range, but doesn't contain any blocks | `200` | Some chains may have gaps in the numbering. The request should not be retried in this case — no blocks will ever appear for such range. |
| The first requested block is below the beginning of the dataset range | `400` | The client should make sure the requested range is within the dataset range |
| The `parentBlockHash` in the request doesn't match the current parent hash for the given `fromBlock` | `409` | See below |

In case of the `503` and `429` codes there may be an additional `Retry-After` header indicating the number of seconds to wait before retrying the request.

### Handling reorgs (forks)

Historical blockchain data is easy to deal with because one can assume that blocks are ordered sequentially and there is only one block for the given height (block number). However, when getting close to the blockchain head, the client has to consider the possibility of chain reorgs.

As a hint about the finalization point, the portal exposes the `/finalized-head` endpoint. It responds with the last block which should be considered "final" meaning that it's unlikely to be reverted. For some datasets it's not possible to guarantee finality for sure, but if the client encounters a reorg deeper than the finalization point, it shouldn't take actions to resolve it automatically, and should signal the error to the user instead.

The portal additionally adds the `X-Sqd-Finalized-Head-Number` and `X-Sqd-Finalized-Head-Hash` headers to each successful response to save additional requests.

With each consequent request to the `/stream`, the client should specify the `parentBlockHash` query field with the known parent hash of the first requested block. The portal will check whether the hash matches the parent hash of the current block number `fromBlock`. If it doesn't, the portal will respond with the `409` error and the list of the previous blocks on the path to the current head. In this case, the client should re-request the blocks starting from the last known ancestor. If no common ancestor was found (chains diverged too much), the client should repeat the procedure for the preceding blocks until the common ancestor is found.

If the hashes match, the portal starts streaming the blocks on the path from the `fromBlock` to the current head. As soon as the block returned in the stream is no longer on the path to the head, the stream is terminated and the procedure repeats.

An example of 409 response:
```json
{
  "lastBlocks": [
    {
      "number": 21780872,
      "hash": "0xf6a96a29423093e947960fcde3cf79730eadacd389fe2ed6cd1c97deb356a12e"
    },
    {
      "number": 21780873,
      "hash": "0xcc44e9d4723600bb3078c5e0ab5df0cf7513df2e12e85f8548c5c469083b19bb"
    },
    {
      "number": 21780874,
      "hash": "0x1dce783bdb93b72af818addd1e97473d64f6e25ab512ce790a89c7f0976f6a0a"
    }
  ]
}
```
