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
    "start_block": 0,
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
Responds with single decimal number — the last available block to be served by the `/finalized-stream` endpoint.\
Note that the first available block is not always 0.

#### `POST /datasets/<dataset>/stream`
TBD

#### `POST /datasets/<dataset>/stream/height`
TBD

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
The request body is a JSON object is a query following the [SQD query format](https://docs.sqd.ai/subsquid-network/reference/evm-api/).

The client **should** pass the following request headers:
- `Content-Type: application/json`
The client **may** pass the following request headers:
- `Accept-Encoding`: one of `gzip` or `deflate`. If omitted, the response will be decompressed by the nginx making streaming less efficient. Once implemented, the `deflate` option should be preferred to avoid decompression.

### Response
The response is a stream of JSON objects in [JSON Lines](https://jsonlines.org/) format, each representing a block. The response may be empty (with `204` status code) indicating that no blocks were found for the given range.

Upon receiving the request, the portal starts streaming the blocks in the order of increasing block numbers. The portal may return any number of blocks before terminating the stream. Due to the streaming nature of the HTTP protocol, it's not possible to communicate the reason of termination to the client. Whenever a successful non-empty response has been received, the client should check the last returned block number and send a follow-up request if more blocks are needed.

Aside from the blocks explicitly requested by the query, the response always contains the first and the last block of the scanned range. It may also contain additional blocks not requested by the client.

If a block with number `N` was received in a response, it is guaranteed that all the existing blocks on the path from the `fromBlock` (from the query) to `N` matching the query are included in the response forming a chain.

### Errors
| Reason | HTTP Code | Details |
|-|-|-|
| Internal error (crash) during request handling | `500` | The request should not be retried because it may be causing the error |
| The chunk exists, but no worker is ready to serve it | `503` | The request should be retried later |
| All the workers rate limited this portal | `429` | Should be retried after the specified delay |
| The query is invalid | `400` | The request should not be retried |
| The dataset is not found | `404` | The client should only request datasets from the list returned by `/datasets` |
| Invalid endpoint | `404` | |
| The requested block range is out of dataset range | `204` | If the `/height` is less than the end of the requested range, those blocks may be present later |
| The requested block range falls into the dataset range, but doesn't contain any blocks | `204` | Some chains may have gaps in the numbering. This case should be treated the same way as the above — if the request had a bounded range, the querying loop ends immediately (no more data right now), otherwise a new matching block may arrive later. |
| The first requested block is less than the beginning of the dataset range | `400` | The client should make sure the requested range is within the dataset range |
| The `parentBlockHash` in the request doesn't match the current parent hash for the given `fromBlock` | `409` | See below |

In case of the `503` and `429` codes there may be an additional `Retry-After` header indicating the number of seconds to wait before retrying the request.

### Real-time mode
Before reaching the finalized head, the client may assume that there are no rollbacks (forks) and the blocks are ordered sequentially. After that, if the client wants to get the latest data, it should switch to the real-time mode and use the `/stream` endpoint. The above statements still apply for it, but there are additional considerations.

With each query, the client should pass the `parentBlockHash` field of the known parent hash of the first requested block. The portal will check if the hash matches the current parent hash for the given `fromBlock`. If it doesn't, the portal will respond with a `409` error with the list of the previous blocks on the path to the current head. In this case, the client should re-request the blocks starting from the last known ancestor.

If the hashes match, the portal starts streaming the blocks on the path from the `fromBlock` to the current head. As soon as the block returned in the stream is no longer on the path to the head, the stream is terminated and the procedure repeats.

The portal additionally adds the `sqd-finalized-head-number` and `sqd-finalized-head-hash` headers to the response, indicating the current finalized head number and hash.
