# Scheduling algorithm

## Goals

* Distribute all the available chunks among the existing workers to maximize data availability while minimizing the number of required downloads.
* Assign each active Worker on the Network a list of chunks and allow them to always fetch it from an external source (the worker state may be lost).
* Ensure higher availability for more popular datasets.
* Utilize the Workers’ storage capacity as much as possible.
* Use a stateless assignment algorithm, i.e., the assignment can be fully reproduced from input parameters.

## Input data

### Data chunks

The data chunks from all configured datasets are listed from S3 storage, and this list is cached in ClickHouse for faster access.
Without this caching a single listing of Solana dataset takes several minutes.

### Worker performance

The Scheduler reads the pings (and possibly logs) data from the ClickHouse to evaluate Workers’ reliability.

The Workers with low uptime and/or suspicious behavior are marked as *unreliable*. *Unreliable* Workers continue participating in the Network and get assigned chunks, but the Scheduler aims to assign all the data chunks to enough *reliable* workers.

### Priorities

In the initial phase, the priorities will be manually assigned to the entire datasets instead of individual chunks.

Priorities are relative numbers indicating how popular the dataset is compared to others. If the priority of dataset A is `k` times more than the priority of dataset B, the Scheduler will try to assign `k` times more replicas of dataset A to the Workers than dataset B.

In the future, priorities may be automatically assigned based on the historical queries, but it’s out of a scope now.

## Solution

The proposed algorithm is based on Google’s paper [“Consistent Hashing with Bounded Loads”](https://research.google/blog/consistent-hashing-with-bounded-loads/) with modifications achieving distribution quality closer to [Rendezvous hashing](https://github.com/kalabukdima/scheduler-design/blob/master/report/report.pdf) while still preserving the performance benefits of [Consistent Hashing](https://en.wikipedia.org/wiki/Consistent_hashing).

### The core algorithm

![image](https://github.com/user-attachments/assets/594120f9-fee0-45ad-b1e6-a10574f7fb71)

There are `N` workers with limited capacity and `M` data chunks with known sizes.

First, the **replication factors** are calculated for each dataset based on the priorities and the target capacity. The target capacity is the total storage capacity of all Workers multiplied by **saturation factor** (default is $$0.99$$).
For each chunk we then spawn a fixed number of "**virtual chunks**", so that each virtual chunk is assigned to a single Worker.

Then `K` "**rings**" are generated, and each worker is assigned a pseudo-random position on each ring based on the hash of its PeerID and the ring number.

After that each virtual chunk is seqentially (in the alphabetical order of their IDs) assigned to the Workers like this.
- The ring number is chosen simply by taking the modulo of the virtual chunk hash by `K`.
- The chunk ID is hashed to get its position on that ring.
- The closest worker clockwise from that position with enough capacity is chosen for this chunk. If the worker already has this chunk assigned, it's also skipped.

### Notable qualities

- If `K=1`, the proposed algorithm corresponds to the Consistent Hashing.
- If every chunk is assigned to a unique ring (`K>=M`), the algorithm corresponds to the Rendezvous hashing.
- With `K ~ log(M)`, the algorithm achieves as good distribution quality as Rendezvous hashing while still being fast enough to run in a few seconds for the entire Network.
- The time complexity is $$O(K N \log N + \tilde{M} \varepsilon \log N)$$ where $$\tilde{M}$$ is the number of virtual chunks and $$\varepsilon$$ is the number of Workers dismissed per chunk (stays low in practice).
- It's consistent in respect to the set of Workers and the set of chunks, but not to the value of `K`. It's possible to design an algorithm that is consistent in respect to `K`, but it adds a significant performance overhead. The `K` has been set to `6000`.

### Unreliable workers

The core algorithm is executed twice: first, with only the *reliable* Workers to get the assignment for them, and then with all Workers to get the assignment for the *unreliable* Workers. This way, when Workers become reliable, they will get approximately the same assignment as they had before.

## Output data

As a result of the algorithm, the Scheduler produces an [assignment](./02_assignment_lifecycle.md) file that contains the list of Workers and the chunks assigned to them, and stores it in S3. It also stores the metadata files:
- Network status — the JSON file used by the Network UI to display worker statuses (https://metadata.sqd-datasets.io/scheduler/mainnet/status.json)
- Prometheus metrics — since it's a cron job that only runs periodically, the metrics are stored in a S3 file (http://metadata.sqd-datasets.io/scheduler/mainnet/metrics.txt)

---

The details on how the assignment is published and read are covered in the [next page](02_assignment_lifecycle.md).