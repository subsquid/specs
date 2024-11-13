# Collecting query logs

## Goals

* Collect and store enough data to be able to verify the response of any query.
* If network conditions allow for it, collect the logs for **all** executed queries from the Workers.
  These logs will be used to calculate the rewards.

## Implementation

> Currently, the Logs Collector listens for the logs pushed from both Workers and Gateways.

### Worker logs

* Workers have a local SQLite storage and save a log entry before sending a response.
  Each log has a `timestamp` (obtained from and signed by client) and a globally unique `query_id`.
* Logs Collector actively requests the Workers to fetch the existing logs.
  Each such request contains the `from_timestamp` — the earliest time of the logs that should be returned.
  The request may also include the `query_id` of the last log already collected from this Worker.
  This is done to allow to collect multiple logs with the same timestamp iteratively in case they don't fit in a single message.
* Upon receiving such a request, the Worker finds the first log to send to the collector (either by locating a `query_id` in its local DB or by filtering by the `from_timestamp`)
  and sends as many logs starting from it (in the order they appear in the DB) as fits in the message.
  If there are no more logs left, it sets the `drained` flag in the response.
* After receiving a response, the Logs Collector stores the received logs in permanent storage. It repeats the procedure until all logs from the current Worker are collected.
* The Worker periodically removes stale logs (older than 40 mins) from the DB to not overuse the disk if logs are not being collected.

### Gateway logs

Collecting logs from gateways is not as straightforward because they [can’t be used as request servers](04_network_communication.md#nat-limitations).

These logs are broadcasted by the Portals and listened by the Logs Collector.
Broadcast is used instead of direct messages to allow horizontal scaling of the Logs Collector in the future.

See the details on the [Network Communication page](04_network_communication.md#client-portal-logs).