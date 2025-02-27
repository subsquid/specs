# Tokenomics 2.1

## Overview

Tokenomics 2.1 addresses the centralization issues of Tokenomics 2.0, namely:

- That there is a single (de-facto centralized) pool for providing SQD for yield, which makes SQD a security
- The lack of dynamic pricing and many parameters that has to be hard-coded/adjusted in a centralized (or, at best, DAO-like) fashion. The subscription fee is not established by an open market and the marketplace. 
- Removing the treasury-initiated buyback-and-burn mechanics which makes SQD a security
- Moving the reward token out of scope
- Introducing the fee switch to the Portals (to be activated in the future if necessary)
- Making it possible to register Portals on EVMs (in particular, Base) and Solana. For Solana users, it opens up the posibility to pay in USDC or SOL.


## The SQD Flows

**Workers** 
Workers serve the data and receive rewards in SQD. The reward depend on the number of served queries, the amount of delegated tokens and the uptime of the worker. The worker has to lock 100k SQD to participate in the network. The maximal amount of rewards distributed per worker and the delegators is controlled by a single parameter called `TARGET_APR`. The reward is then split abetween the worker and the delegators for the worker.  

**Delegators**
Delegators delegate SQD to workers to get a part of the worker reward. Both the amount of delegated tokens and the served queries affect the reward per query served. 

**Data consumers**
Data consumers query the network p2p using a Portal. The maximal bandwidth that can be consumed by a Portal is determined by the amount of SQD locked in the Portal contract. Thus, the data consumer either buys SQD on the open market and locks the desired amount themselves, or makes an _SQD Provision Offer_ to SQD holders willing to provide SQD in return to the fee. 

An SQD Provision Offer is an agreement to lock SQD for a specified amount of time for a fee, paid as continuosly during the whole lock period. The fee is locked by the consumer in advance and can be paid in any of the supported tokens. Special conditions apply for extending the provision offer and withdrwals. 

**SQD providers**
SQD providers hold SQD and fullfill the matching _SQD Provision Offers_. Active providers can advertise their target fees in advance to make the market and set the expectations for the data consumers. 

## Emission reduction

The `TARGET_APR` currently set to 25% yearly, will be gradually reduced and replaced by the fees collected from the portals. 

## Portal Payments

The are two options to get data through the portals:
- Lock SQD tokens (the existing flows)
- Pay a subscription fee in one of the supported tokens, so that the SQD is locked by one or multiple SQD providers. 

**The subscription flow**

The user specifies:
- the required bandwidth (which translates into the required SQD to be locked)
- the terms (fix-term or auto-extension)
- the price (the dApp will provide the current quotes of the SQD providers to give a reasonable offer)

The user:
- creates a Portal Registration Contract
- makes the fee deposits
- the willing SQD providers lock the SQD for the required term

The fee is deducted every epoch and automatically split:
- 50% to the SQD providers
- 45% to the worker reward pool
- 5% gets burnt

The fee parameters are adjustable. 

![image](https://gist.github.com/user-attachments/assets/9d3977ee-aa80-4a6f-a248-83656abc10e1)


## The fee switch

Apart from the fees collected from the subscription fees, Tokenomics 2.1 introduces a fee switch directly to the portals.
The fee switch is initiall set to zero, but can be switched on at a later time.

When it is on, the fee is deduced from SQD locked in every Portal contract, and distributed between burn and the reward pool.
That way even the users self-staking SQD will pay a usage tax. For SQD providers the tax may be compensated directly by the fee. 


## Deployments to Solana and other networks

The Poral Registration factories allow deployments on foreign networks, such as Base and Solana, assuming the two-way bridging is possible. In order to integrate a foreign chain one would need

- Update the Worker nodes to listen to the registration events
- Establish a canonical "bridged" token on the target chain with minimal liqidity pools
- Implement bridging of the fees to be teleported to the host chain regularly, to top up the reward pool on the host chain