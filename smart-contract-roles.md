# Smart Contract Roles

This document describes the roles for the first iteration of the platform. This documents is not a formal spec nor is an endorsement of any form. The actual implementation may differ from this proposal.

## `SUDO`

This is a super-user role allowing to change the proxy implementations of the contract proxies. This role can also assign arbirtrary role to other accounts, including `SUDO`. Any `SUDO` action is subject to a clawback period during which any account with `VETO` role can cancel the action. 

## `TEAM_VESTING_ADMIN`

This role allows to terminate vesting for a team member 
and markup vesting allocation for new team members from the Team funds.

## `TREASURY_ADMIN`

Only accounts with this role are allowed to spend the treasury funds. This includes access to unlocked funds of Treasury, Operations, Airdrop, Exchange Liquidity, Partnerships, Liquidity Mining, Infra Provider Incentives

It DOES NOT have access to:

- Team
- Early Backers and Backers
- Strategic Round
- Strategic Round II

Each spending is subject to a clawback period during which `VETO` holders can  the transfer. 

## `GRANTS_ADMIN` 

This roles allows to issue grants in the form of stakable but non-spendable funds from the Infra Provider Incentives account. 

## `VETO`

Accounts with this role are allowed cancel transaction during the clawback period by casting a `VETO` vote to any `SUDO` actions or `TREASURY_ADMIN` spendings. 

## `VETO_ADMIN`

This role can grant/revoke `VETO` roles. 