# Node registration

## Workers

A Worker has to be registered by locking 100,000 SQD in the [smart contract](https://github.com/subsquid/subsquid-network-contracts/blob/5f07739900de708ce03223a9163aa694356c773e/packages/contracts/src/WorkerRegistration.sol). During the lock period, it can participate in the Network and is eligible for the rewards.

## Gateways (Portals)

A Gateway cluster can be registered in the Network by locking at least 10,000 SQD in the [smart contract](https://github.com/subsquid/subsquid-network-contracts/blob/5f07739900de708ce03223a9163aa694356c773e/packages/contracts/src/WorkerRegistration.sol).

After that, up to 10 peer IDs can be associated with this cluster, allowing each of them to participate in the Network as a Gateway.

## Whitelisting

Each node on the Network periodically (how often?) reads the contracts’ states through the RPC node to get the list of peer IDs allowed to participate in the Network. The node then only accepts p2p connections from the peers on this list. All the other packets are dropped.

## Migrating a node

TODO: describe precautions that can be done to forbid using the same peer ID from multiple machines simultaneously.