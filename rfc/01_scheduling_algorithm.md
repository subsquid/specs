# Scheduling algorithm [WIP]

## Goals

* Distribute all the available chunks among the existing workers to maximize data availability while minimizing the number of required downloads.
* Assign each active Worker on the Network a list of chunks and allow them to always fetch it from an external source (the worker state may be lost).
* Ensure higher availability for more popular datasets.
* Utilize the Workers’ storage capacity as much as possible.
* Use a stateless assignment algorithm, i.e., the assignment can be fully reproduced from input parameters.

## Input data

### Historical data

The Scheduler reads the pings (and possibly logs) data from the ClickHouse to evaluate Workers’ reliability.

The Workers with low uptime and/or suspicious behavior are marked as *unreliable*. *Unreliable* Workers continue participating in the Network and get assigned chunks, but the Scheduler aims to assign all the data chunks to enough *reliable* workers.

### Priorities

In the initial phase, the priorities will be manually assigned to the entire datasets instead of individual chunks.

Priorities are relative numbers indicating how popular the dataset is compared to others. If the priority of dataset A is `k` times more than the priority of dataset B, the Scheduler will try to assign `k` times more replicas of dataset A to the Workers than dataset B.

In the future, priorities may be automatically assigned based on the historical queries, but it’s out of a scope now.

## Solution


:::info
The proposed algorithm is completely different from what is currently being used.

:::

Basically, a combination of [this approach](https://github.com/kalabukdima/scheduler-design/blob/master/report/report.pdf) (Rendezvous hashing) with Google’s paper [“Consistent Hashing with Bounded Loads”](https://research.google/blog/consistent-hashing-with-bounded-loads/), fit in reasonable performance limitations.

TBD


---

The details on how the assignment is published and read are covered in the [next page](02_assignment_lifecycle.md).