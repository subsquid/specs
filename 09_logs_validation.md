# Logs validation

Workers send logs which are used for further reward distribution. The logs may and should be validated to ensure that the Worker is not trying to cheat. Multiple assertions can be validated offline, after the logs have been collected.

* Worker is doing useful job — the executed queries had been issued by a valid client using [allocated CUs](06_compute_units_allocation.md).
* Worker is usually responding with correct results. We can't guarantee (without client-side performance overhead) that every response is valid, but the penalty for cheating should be high enough to make any attempts to cheat unprofitable.

## Solution

<img src="https://github.com/user-attachments/assets/3dc1d7f6-663a-4aaa-aa5a-827b331ffaae" width="800" />


### Worker is doing useful job

* The client always sends a signature of the query together with the query.
  This signature acts as a certificate that the Worker didn't make up a query.
* The signed message contains the query ID, query data (query string, dataset, block range), Worker's ID and a timestamp. It doesn't allow the Worker to use an existing signature with any other query.
* The Worker sends this signature together with the query log.
* We can then ensure that the number of queries executed by the Worker issued by the given client doesn't exceed the maximum allowed number of queries per epoch for that client.
  Despite timestamps being inaccurate, the outliers (2x the allowed amount) can be easily detected.

### Worker is usually responding with correct results

* The Worker sends the query result hash with query logs.
* The Worker sends the same hash and a commitment to it back to the client.
* The commitment is a signature of the message containing the query ID and the result hash.
* The client may optionally check whether the hash and the signature are valid. If any of them doesn't match, the client blacklists this Worker and doesn't send it queries for some period.
* The client tries to send the log (which is not guaranteed to be collected), including Worker's commitment.
* Whenever we encounter both Worker's log and client's log with the same query ID and a valid Worker's signature, we can check that the client received the same result the Worker claims (in the query log) it sent.
  (If the signature is invalid, we can't know whether it was sent by the Worker or tampered by the client.)
* For all Worker's logs, even without matching client's log, we can reproduce the query, calculate the result hash and check the Worker's log.
* If the result hash matches the actual result, the client has the same result hash, and the data received by the client matches the hash, it guarantees that the Client has received the correct result.
  See [incentivization](#incentivization) below for further analysis

## Incentivization

### Client

The clients' goal is to receive the correct results as soon as possible.
Therefore, they should cooperate with the Workers for the best results.\
For example, sending an invalid query signature is unprofitable for the client,
because the Worker will probably refuse responding to such query since it won't get the rewards for it.

If it's critical for the client to receive the correct data, it should verify every response (recalculate the hash and verify Worker's commitment).
It may also prefer to send the query to multiple Workers and compare the results.

Validating the response commitment doesn't guarantee that the response itself is valid.
Therefore, the clients are incentivized to send logs so that the malicious Workers may be identified and excluded from the Network (see below).

Any tampering of the Worker's commitment to the response is not profitable for the client because client's log with invalid commitment will simply not be used.

### Worker

The Workers's goal is to submit as many query logs as it can because the rewards depend on it.
Since the logs are only valid if issued by some client with allocated CUs, the Worker is incentivized to receive new queries. (It's assumed that running its own client to generate extra queries is unprofitable.)
Therefore, it's dependent on the clients and is incentivized to cooperate with them to get the rewards.

If the client encounters an invalid response (the Worker tried to send data which differs from the hash or an invalid commitment), it wouldn't want to query that Worker again since it's probably intentionally malicious.

The Worker can't know whether the client will verify its response, but in case of being caught it's deprived of the queries coming from this client.
As the result, the Worker is incentivized to send the valid commitment to the response to the client.

The client's logs are not guaranteed to be received, but if they are, we can validate that the commitment to the client corresponds to the hash in the logs sent by the Worker, and if it doesn't, the Worker's stake may be slashed/frozen.\
Since the Worker can't know whether the client's log will reach the Logs Collector, it's unprofitable for it to risk sending a valid commitment to the result not matching its logs.
Therefore, the Worker is incentivized to send logs with the same result hash as it sends to the client.

Finally, we can pick any Worker's log, reproduce the query and check whether the result hash sent by the Worker is correct and slash/freeze its stake if it's not.
So the Worker will definitely not want to send logs with invalid response hashes.\
It means that the Worker is incentivized to send the correct result both in the logs and to the client.

### Other parties

The goal of someone not participating in the Network may be to disrupt it by sending fake messages.
This section doesn't cover DoS and similar attacks, only abusing the logs validation process.

To send any message to the Network, you have to be registered either as a Worker or as a Portal (client).
Note that both ways require locking some SQD, so it's already costly.

#### Forcing stake slash

We may only slash the stake in two cases:
* the Worker has sent the log with incorrect result hash;
* the client has sent the log with the valid Worker's signature committing to the invalid data.

In both cases, such message is signed by the Worker itself, so other parties can't affect it without tampering the signature.

#### Giving invalid data to the client
A Worker that is not incentivized by the rewards may indeed try to send invalid results.
It may even be profitable if the cost of damage is much higher than (expectation of) the cost of slashed SQD.
This validation mechanism doesn't fully protect us from that. For full verifiability we should use ZK proofs or TEE computation.
