# HotBlocks Service Level Indicators (SLI) and Objectives (SLO) Specification

## Overview

This document defines the Service Level Indicators (SLI) and Service Level Objectives (SLO) for the HotBlocks real-time blockchain data service. These metrics ensure reliable, low-latency access to blockchain data for Subsquid users.

## Service Level Objectives (SLO)

### Tier 1 Networks (Starting with Solana)

- **Real-time Latency**: 99% of blocks available within 500ms of block availibilty 
- **Service Availability**: 99.9% HotBlocks service uptime

## Service Level Indicators (SLI)

### 1. Real-time Latency Metrics

#### Currently Implemented
- **Block Processing Time** (`portal_block_processing_time_ms`)
  - Measures time from block ingestion to portal availability
  - Histogram buckets for percentile calculations
  - Tracks percentage of blocks processed < 500ms over 24h periods

- **Block Lag Metrics** (`sqd_hotblocks_block_lag_ms`)
  - Time between block minting and ingester receipt
  - Per-provider breakdown for performance comparison

- **Latest Block Processing Time** (`portal_latest_block_processing_time_ms`)
  - Real-time tracking of most recent block processing latency
  - Source-specific measurements

#### To Be Implemented
- End-to-end propagation time (validator broadcast to API availability)
- Network-specific latency baselines

### 2. Service Availability Metrics

#### Currently Implemented
- **Blocks Processed Rate** (`sqd_hotblocks_last_block`)
  - Blocks per second/minute by provider
  - Indicates service health and throughput

- **Head Position Tracking**
  - Portal head lag vs data service head
  - Stored blocks count
  - Finalized vs unfinalized block tracking

#### To Be Implemented
- **Service Uptime Percentage**
  - HTTP endpoint availability (2xx response rate)
  - Calculated over rolling 24h, 7d, 30d windows

- **Error Rate Metrics**
  - Failed block retrievals
  - Timeout occurrences
  - Data corruption/validation failures

- **Recovery Time Metrics**
  - Time to restore service after outage
  - Catch-up rate after downtime

### 3. RPC Connectivity Metrics

#### To Be Implemented
- **RPC Response Times**
  - Per-provider response time histograms
  - Peak vs off-peak performance

- **RPC Node Availability**
  - Individual provider uptime percentages
  - Network-wide RPC availability

## Measurement Implementation

### Data Collection
- Prometheus metrics with appropriate labels (network, source, dataset)
- Histogram buckets optimized for sub-second latencies
- Consistent labeling across all services

### Dashboard Requirements
- Real-time SLO compliance visualization
- Historical trend analysis (24h, 7d, 30d)
- Per-network and per-provider breakdowns
- Alert thresholds aligned with SLOs

### Alerting Strategy
- Proactive alerts at 95% of SLO threshold (once the SLO is met and stable)
- Critical alerts on SLO breach (once the SLO is met and stable)

## Review and Updates

This specification should be reviewed quarterly and updated based on:
- Actual performance data
- User feedback and requirements
- Network expansion (adding new Tier 1 networks)
- Technical improvements in monitoring capabilities

---

*Last Updated: 02.07.2025*
*Version: 1.0*