# Sending queries

## Goals

* Ensure queries can be sent from Portals to Workers with the minimal possible latency.
* Ensure the responses can be received reliably.
* Allow verifying responses later.

## Implementation

### Queries

Whenever the Portal wants to query the Worker, it first opens a direct connection to that Worker as described [here](04_network_communication.md#queries).
Then it generates a unique query ID (UUIDv4), sings the `Query` message and sends it to the Worker.

The block range is usually included in the query string, but Portal may override it by setting the `block_range` field in the message and pass the original query string without modification.

See [Logs validation](09_logs_validation.md) for the details about signing the query.

The successful response contains the `last_block` field. It can be used to send a continuation query.

The error response may contain a `retry_after` hint, suggesting that any attempt to send a query before that timeout will fail.

### Datasets

TODO: describe how the Portals discover new datasets and use their IDs.
