# Portal API

The portal exposes the HTTP API with the following methods

### `GET /status`

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

### `GET /datasets`

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
    "real_time": true
  },
]
```

### `GET /datasets/<dataset>/metadata`

Responds with the information describing the dataset as a JSON object. Contains at least the following fields:
- `dataset` — the default name used to reference this dataset.
- `aliases` — an array of alternative names that can be used interchangeably with the default name, e.g., in the HTTP endpoints.
- `real_time`, indicating whether the portal has real-time data for this dataset.
- `start_block` — the block number of the first known block in the dataset. The client should not request any blocks below this number.

Response example:
```json
{
  "dataset": "ethereum-mainnet",
  "aliases": ["eth-main"],
  "start_block": 0,
  "real_time": false
}
```

### `GET /datasets/<dataset>/state`

Responds with a summary of stored block ranges for the given dataset. May be used for displaying network status in the UI.\
TBD

### `POST /datasets/<dataset>/stream`

Accepts a [data query](https://github.com/subsquid/data/blob/f78261e3d816de1e20a38460652125d88e4a2987/crates/query/src/query/mod.rs#L15) as a JSON body and, in case of success, returns a list of matching blocks.

Data query (among other options) has the following fields:

* `fromBlock` — the number of the first block to fetch (required)
* `toBlock` — the number of the last block to fetch (inclusive) (optional)
* `parentBlockHash` — expected hash of the parent of the first requested block (optional).

The client **should** pass the following request headers.
- `Content-Type: application/json`

The client **may** pass the following request headers.
- `Accept-Encoding: gzip`. If omitted, the response will be decompressed by Nginx, making streaming less efficient.
- `Content-Encoding: gzip`, if the request body is compressed.

> TODO: allow setting custom finality confirmation.

This endpoint can produce the following responses, differentiated by HTTP status.

#### 200 OK

A list of blocks in the form of [gzipped](https://www.rfc-editor.org/rfc/rfc1952) [JSON lines](https://jsonlines.org/) body, with each JSON object representing a block.

The portal may return any number of blocks before terminating the stream. Due to the streaming nature of the HTTP protocol, it's not possible to communicate the reason of termination to the client. Clients are supposed to check the `number` (and `hash`) of the last returned block and to send subsequent requests if more blocks are needed.

The returned list may contain blocks that don't match the query filters. They are added to designate the chain scanning progress.
In particular, the first existing block with `block.number >= query.fromBlock` is always included. For every blockchain, except for Solana, the above condition can be replaced with equality, i.e., `first_returned_block.number == query.fromBlock`.

Blocks in the list are guaranteed to be sequentially ordered and to belong to the same chain.

If some block `block` has been included in the response, it is also guaranteed that all the existing blocks on the chain from `query.fromBlock` to `block` matching the query are also included in the response (no matching blocks are skipped).

The list of blocks may only be empty if all the following conditions are met:
- the requested dataset is Solana,
- the data query has a bounded range (both `query.fromBlock` and `query.toBlock` were specified),
- the entire range of blocks requested by the query has been [skipped](https://solana.com/docs/terminology#skipped-slot).

If `query.parentBlockHash` has been specified, it is also guaranteed that `first_returned_block.parent_hash == query.parentBlockHash`.

#### 204 No Content

No content response, indicating that the range of blocks requested by the query lies entirely above the latest block available in the dataset.

If real-time data is enabled for the dataset, the portal waits up to 5 seconds for the arrival of new blocks before returning `204`.

#### Finalized head headers

Both `200` and `204` responses may include `X-Sqd-Finalized-Head-Number` and `X-Sqd-Finalized-Head-Hash` headers indicating the `number` and the `hash` of the latest finalized (unlikely to be reversed) block available in the dataset.

Every returned `block` and `block` designated by `query.parentBlockHash` is guaranteed to belong to the same chain with the finalized head block. In particular:

1. `X-Sqd-Finalized-Head-Hash` is a descendant of `block`, when `block.number <= X-Sqd-Finalized-Head-Number`
2. `X-Sqd-Finalized-Head-Hash` is an ancestor of `block`, when `block.number >= X-Sqd-Finalized-Head-Number`

For some datasets, it's not possible to guarantee finality for sure, but if the client encounters a reorg deeper than the finalization point, it shouldn't take any actions to resolve it automatically and should signal the error to the user instead.

#### 409 Conflict

This response indicates that the `parentHash` of the first block requested by the query does not match `query.parentBlockHash`.

The response body is a JSON object with a single `previousBlocks` array — the list of previous blocks that belong to the current chain.

The list contains `{number, hash}` pairs and may have an arbitrary length, but is guaranteed to contain at least the parent of the first requested block.

In this case, the client should re-request the blocks starting from the last known ancestor. If no common ancestor has been found (chains diverged too much), the client should request the previous blocks until a common ancestor is found.

**Response example:**
```json
{
  "previousBlocks": [
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

#### 400 Bad Request

Possible causes:
- the request headers or body encoding are incorrect,
- the query is invalid (the response body contains the error message in this case),
- the `fromBlock` is below the dataset's `start_block`.

In any case, the client should not retry the request.

#### 404 Not Found

Possible causes:
- a wrong endpoint has been requested,
- the dataset has not been found.

#### 429 Too Many Requests

The client has exceeded the rate limit. The client should retry the request later. The rate limit may be increased by allocating more [compute units](./06_compute_units_allocation.md) to the portal.

The response may include the `Retry-After` header indicating the number of seconds to wait before retrying the request.

#### 503 Service Unavailable

The server could not process the request at the moment. The client should retry the request later.

The response may include the `Retry-After` header indicating the number of seconds to wait before retrying the request.

#### 500 Internal Server Error

The server failed to process the request. The client should not retry the request because it may be causing the error.

### `POST /datasets/<dataset>/finalized-stream`

Same as `/datasets/<dataset>/stream`, but only returns the finalized blocks. The notion of finality here is up to the implementation and may vary between datasets. The current implementation only returns the blocks obtained from the SQD Network.

### `GET /datasets/<dataset>/head`

Returns JSON object with `.number` and `.hash` of the highest block available in the dataset. When no block is available, returns _`null`_.

This endpoint is supposed to be used for diagnostic purposes.

### `GET /datasets/<dataset>/finalized-head`

Returns JSON object with `.number` and `.hash` of the highest finalized block available in the dataset. When no finalized block is available, returns _`null`_.

This endpoint is supposed to be used for diagnostic purposes.

## Deprecated endpoints

These endpoints are preserved for compatibility with the old clients and should not be used.

### `GET /datasets/<dataset>/finalized-stream/height`

Responds with a single decimal number — the highest number of the block available to be served by the `/finalized-stream` endpoint.\
Note that the first available block is not always 0.

### `GET /datasets/<dataset>/height`

Same as `/datasets/<dataset>/finalized-stream/height`

### `GET /datasets/<dataset>/<start_block>/worker`

Gets the worker URL for querying the dataset starting from the given block.

### `GET /datasets/<base64_id>/query/<worker_id>`

Sends the query to the worker. The query is passed in the request body.
