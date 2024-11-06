# Data delivery

## Goals

* Provide a stable source of data assigned to the Workers.
* Make workers only download data from another nodes in the network or their own providers. Our centralized storage should be hidden.
* Prefer local network connections for data sharing if possible.
* Use content-addressed assignments to allow trustless downloads from various providers.

## Solution

Use the BitTorrent protocol with IPFS content addressing. The only difficulty is to find (or implement) a client that does not store data on disk in any intermediate format because we can’t afford to store two data copies.

Provide a “pinning” service that would download new data from our centralized (R2) storage and make it available until enough nodes download its copies.


