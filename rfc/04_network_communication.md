# Network communication

# Transport layer: libp2p

The Network communication is based on the [libp2p](https://libp2p.io/). It implies that:

* Each node in the Network is associated with a unique [Peer ID](https://docs.libp2p.io/concepts/fundamentals/peers/). Peer IDs are encoded public keys represented by 73-byte structs in memory and serialized into 52-byte base58 strings.
* Peer authentication is done on the protocol level. If the handler code receives a message with a Peer ID, it can be sure that it has been sent by the owner of the private key associated with that Peer ID.
* Streams are multiplexed internally, so all the p2p communication happens on a single UDP port, and there is only one physical connection per peer, even if there are dozens of communication channels open.

## Pubsub protocol

There is a comprehensive guide in libp2p Docs: <https://docs.libp2p.io/concepts/pubsub/overview/>

Basically, this protocol allows broadcasting a message to all the nodes subscribed to the topic.

Each message is wrapped in the [following struct](https://github.com/libp2p/rust-libp2p/blob/8ceadaac5aec4b462463ef4082d6af577a3158b1/protocols/gossipsub/src/types.rs#L99):

```rust
pub struct RawMessage {
    pub source: Option<PeerId>,
    pub data: Vec<u8>,
    pub sequence_number: Option<u64>,
    pub topic: TopicHash,
    pub signature: Option<Vec<u8>>,
    pub key: Option<Vec<u8>>,
    pub validated: bool,
}
```

## Request-response communication

Two nodes can participate in this type of communication. One of them acts as the “client” and initiates the request, and another acts as a “server”. Note that any node can act as a client for some requests and as a server for other requests.

## Kademlia DHT

The DHT in our case is only used to store the public addresses ([multiaddr](https://multiformats.io/multiaddr/)) of the Workers (but not other members of the Network) and query them by peer ID.\
Such a lookup implies multiple network requests, so it's quite expensive and should be avoided if possible (e.g., by caching the known addresses locally).

## NAT limitations

See this [page](https://docs.libp2p.io/concepts/nat/hole-punching/) (and this [blog post](https://tailscale.com/blog/how-nat-traversal-works)) about why connections between peers behind NAT are not straightforward.

In short, without hosting relay servers, it’s not possible to use a node behind NAT as a request server. Therefore, we have to ensure that such components as Workers and Bootnodes have a public IP without NAT.

## Open questions:

* How many nodes can co-exist in the p2p network without any troubles?
* What happens when multiple nodes join the network?
* What happens when multiple nodes leave the network?
* Can an anonymous (not [whitelisted](05_node_registration.md)) node destabilize the network?
* In what ways can a whitelisted node destabilize the network?
* How long does it take for a gossipsub message to propagate to 95% of nodes if the network has 100/1k/10k nodes?
* How much latency is “reserved” by transport layer encoding, encrypting and other message processing?
* How does libp2p request-response communication relate to the default HTTP requests in terms of performance? What stages does the message pass through?
* Do we get the sender’s address with the gossipsub broadcasted messages?
* Can a request “server” find out whether the response is received successfully?
* Are we using QUIC’s [built-in encryption](https://docs.libp2p.io/concepts/transports/quic/#quic-in-libp2p) instead of the Noise protocol?
* Can we use AutoNAT to emit a warning if the Worker is not publicly available?
* Can we use the [fan-out](https://docs.libp2p.io/concepts/pubsub/overview/#fan-out) mechanism as a channel with a small number of subscribers?
* Are the messages authenticated in the request-response communication? Can we extract the signatures?


# Communication protocol

<img src="https://github.com/user-attachments/assets/efb31758-d38b-4c91-a1b8-3b941a7ed9e7" width=750>

## Pings

### Publisher: Worker

Each Worker periodically (once every 55s) broadcasts its state to the `pings` topic. In particular, it contains a set of available chunks represented as a bit string referencing its latest (linked) assignment.

```proto
message Ping {
  // e.g. "20241008T141245_242da92f7d6c"
  string assignment_id = 1;
  // Points to chunks assigned to this worker in the file referenced by `assignment_id`.
  // 1 on the i-th position means that the i-th chunk is not available.
  BitString missing_chunks = 2;
  string version = 3;  // e.g. "1.0.0"
  uint64 stored_bytes = 4;
}

message BitString {
  bytes data = 1;  // some compressed representation
}
```

If a Worker has 10,000 chunks assigned, its Ping size will usually be less than 1 KB. If it has completed the downloads (probably, at least 95% of the time), it's just a few bytes.

### Subscriber: Portals

Portals subscribe to the Pings topic to discover the Workers and read their available chunks. It also allows filtering by Worker’s version.

### Subscriber: Ping Collector

Ping Collectors subscribe to the Pings topic and write all the Pings they receive to the database (ClickHouse), filtering duplicates on the DB level.


## Queries

Queries are sent from Portals to Workers in a request-response fashion.

### Client: Portal

If the Portal wants to query the Worker, it uses its local cache to find the address by the peer ID.
If the cache entry is missing, it performs the [Kademlia lookup](#kademlia-dht) and saves the discovered address to the cache.\
Then is uses this address to send a direct request to the Worker.

See the [sending queries](07_sending_queries.md) page for the details.

```proto
message Query {
  string query_id = 1;
  string dataset = 2;  // "czM6Ly9ldGhlcmV1bS1tYWlubmV0"
  string query = 3;  // 512 KB max
  // If present, these values should be used instead of from_block and to_block in the query contents
  optional Range block_range = 5;
  
  uint32 timestamp_ms = 6;
  bytes signature = 7;
}
```

### Server: Worker

The Worker accepts any incoming queries from [valid peers](05_node_registration.md), checks the [rate limit](06_compute_units_allocation.md) for this peer, verifies the [signature](09_logs_validation.md) of the message (including timestamp validity) and then tries to process the query against the data chunk in its local storage.

* On error, the Worker sends back the message containing the error description.
* On success, the Worker sends back the query response together with the last block included in the response. If the result doesn’t cover the entire requested range, the client may want to send another request using this last block number.

```proto
message QueryResult {
  string query_id = 1;
  oneof result {
    OkResult ok = 2;
    ErrResult error = 3;
  }
  optional uint32 retry_after_ms = 4;
}

message OkResult {
  bytes data = 1;
  optional uint64 last_block = 2;
  QueryResultSummary summary = 3;
}

message ErrResult {
  oneof err {
    string bad_request = 1;
    string server_error = 2;
    Empty too_many_requests = 3;
    Empty server_overloaded = 4;
    string timeout = 5;
  }
}

message QueryResultSummary {
  optional uint32 size = 1;
  bytes hash = 2;
  bytes signature = 3;
}
```

Note that Workers [must have a public IP](#nat-limitations) to be able to receive requests.


## Worker logs

### Client: Logs Collector

Logs Collectors discover the existing Workers using [Pings](#subscriber-logs-collector) and regularly send requests to collect the saved logs. The exact process is described on [this page](08_collecting_query_logs.md).

```proto
message RequestLogs {
  uint64 from_timestamp_ms = 1;
  uint64 to_timestamp_ms = 2;
  optional string last_seen_id = 3;  // query ID of the last collected query
}
```

### Server: Worker

Workers receive the `RequestLogs` requests and respond with a bundle of query logs. Each log message contains the full [Query](#client-portal) (including the client signature) and some additional statistics. All the fields except the input query have the fixed size. Input query should be limited to 512 KB.

```proto
message QueryLogs {
  repeated QueryExecuted queries_executed = 1;
  bool has_more = 2;
}

message QueryExecuted {
  string client_id = 1;

  Query query = 3;

  oneof result {
    QueryResultSummary ok = 4;
    ErrResult result = 5;
  }
 
  optional uint32 exec_time_ms = 6;
}
```


## Client (Portal) logs

Collecting client logs is more complicated because clients may be [behind NAT](#nat-limitations) and can’t be reliably used as request servers. However, these logs are purely informational, and losing some of them is affordable.

The client logs are broadcasted to the pub-sub topic for anyone interested in them to listen for. This allows adding new Logs Collectors without affecting the existing Portals.

Every participant of the topic **rate limits** the number of forwarded messages to not overload the Network.

### Publisher: Portals

Portals [fan-out](https://docs.libp2p.io/concepts/pubsub/overview/#fan-out) their logs to the topic subscribers and don’t participate in message forwarding themselves.

```proto
message QueryFinished {
  string worker_id = 1;
  string query_id = 2;

  uint32 total_time_ms = 3;
  oneof result {
    QueryResultSummary ok = 4;
    ErrResult result = 5;
  }
}
```

### Subscriber: Logs Collector

Logs Collectors listen for incoming query logs from Portals and store them in the DB (ClickHouse) filtering duplicates on the DB level.

Later, these logs may be used for [response validation](09_logs_validation.md).