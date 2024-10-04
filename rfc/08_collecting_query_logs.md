# Collecting query logs

## Goals

* Collect and store enough data to be able to verify the response of any query.
* If network conditions allow for it, collect the logs for **all** executed queries from the Workers.\nThese logs will be used to calculate the rewards.

## Implementation


:::info
Currently, the Logs Collector listens for the logs pushed from both Workers and Gateways.

:::

### Worker logs

* Workers have a local SQLite storage and save a log entry before sending a response. Each log is assigned a `seq_no` — the number of logs stored by this peer previously. Each log is therefore uniquely identified by the pair (`peer_id`, `seq_no`).
* Logs Collector actively requests the Workers to fetch the existing logs. Each such request contains the last `seq_no` of the log collected from this peer.
* Upon receiving such a request, the Worker sends back the pack with as many of the oldest stored logs as fits in the message size (TBD: what is the limit?). It also sends the `seq_no` of the last stored log.
* If the Logs Collector acknowledges receiving the response, the Worker removes sent logs from its local DB.\n(TODO: if acks are not straightforward in libp2p, consider another approach).
* The Worker periodically removes stale logs (older than 40 mins) from the DB to not overuse the disk if logs are not collected.
* If the Worker has lost it’s state (and upon first initialization), it waits for the next request from the Logs Collector to find out the `seq_no` to start from. Until that, no logs are stored, and the queries are (optionally) not executed.
* After receiving a response, the Logs Collector stores the received logs in the permanent storage and sends back an acknowledgement in case of success. It also checks the `last_seq_no` in the response to find whether this peer has more logs to be collected.

### Gateway logs

Collecting logs from gateways is not as straightforward because they [can’t be used as request servers](04_network_communication.md#nat-limitations).

The proposition is to broadcast logs from the gateways and listen for that (probably lossy) broadcast on the Logs Collector. Broadcast is used instead of direct messages to allow horizontal scaling of the Logs Collector in the future.

TBD…