# SQD specs and RFCs

Specifications, RFCs, and research notes for [SQD](https://sqd.dev). SQD is an open data platform for Web3, including the SQD Network (a decentralized data lake) and the SQD Portal data API. This repository holds design documents, not running code.

## What is in here

The repository is organized into three areas.

### `network-rfc/`

An RFC describing the architecture of the SQD Network: the desired state of the network and the processes that run within it. The overview is in [`network-rfc/README.md`](network-rfc/README.md), with individual documents covering:

- Scheduling algorithm and assignment lifecycle
- Data delivery and network communication
- Node (worker and portal) registration
- Compute units allocation
- Sending queries, collecting query logs, and logs validation
- Distributing rewards
- Portal API and portal configuration

The RFC also describes the network components it refers to: workers, portals (network gateways), bootnodes, the logs collector, the pings collector, the scheduler, and data storage. An Excalidraw source file (`network-rfc/sqd_network.excalidraw`) and diagram attachments are included.

### `SLOs/`

Service Level Indicator (SLI) and Service Level Objective (SLO) specifications. [`SLOs/hotblocks.md`](SLOs/hotblocks.md) defines the SLIs and SLOs for the HotBlocks real-time blockchain data service, including latency and availability targets and the metrics used to track them.

### `sql-research/`

Research notes, design documents, and meeting minutes related to SQL query engine work over SQD data, including DuckDB and Trino investigations. [`sql-research/0000-repos.md`](sql-research/0000-repos.md) lists the related prototype repositories. The `sql-research/papers/` directory holds reference papers (PDFs) cited by these notes.

## Documentation

For product documentation, see:

- SQD docs: https://docs.sqd.dev
- SQD Network docs: https://docs.sqd.dev/en/network

## License

GNU General Public License v3.0. See [`LICENSE`](LICENSE).
