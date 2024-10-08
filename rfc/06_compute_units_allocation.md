# Compute units allocation

## Goals

* Restrict the number of queries running in the Network.
* Encourage clients to obtain SQD tokens to use the Network.
* \*Guarantee that the Workers can handle the queries they receive.

## Solution

<img src="https://github.com/user-attachments/assets/235930d8-6f44-4d4e-89e5-e7267ae7d703" width="800" />

### Allocation process

To be able to use the Network, the client locks SQD tokens in the contract. The minimal locking amount is 10,000 SQD.
1 SQD equals 1 compute unit or more, if locking for a long period.

The allocated compute units (CUs) are associated with the wallet and allow running a cluster of Portals sharing a pool of compute units.
Up to 10 Portals may be registered for a single cluster.

The allocated CUs are assigned to the registered Workers using a strategy defined by a smart contract.
The default strategy splits all CUs equally among the Workers.

Currently, one CU allows to run one query of any kind.

### Rate limiting

Now each Worker has a fixed number of CUs allocated for a given cluster of Portals per epoch.\
The Worker calculates the rate limit for this cluster as `(CU per epoch) / (epoch length)`.
This will be the average rate _R_ at which this cluster of Portals is allowed to send queries.

To allow some request bursts without threatening the stability, the Token bucket algorithm is used.
* A token is added to the bucket every _1 / R_ seconds.
* The bucket can hold at the most _B_ tokens. If a token arrives when the bucket is full, it is discarded.
* When a request arrives and there is at least one token in the bucket, the token is removed and the request is processed.
* If there are no tokens left, the request is discarded as being rate limited.

The Worker also has a limit on the number of queries being processed concurrently.
If a new query passes the rate limit check but the query queue is full, the request is discarded with the "service overloaded" error.\
Note that the value _B_ is chosen to be small enough so that a single client can never overload the Worker.
