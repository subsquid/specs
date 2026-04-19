# Frictionless Payments for Revenue Pools

## Summary

The goal of this initiative is to remove the biggest onboarding friction between Web2 users and Web3 participation in SQD Revenue Pools.

Today, participating in a pool requires users to understand wallets, buy tokens, move assets onto the correct network, and complete an onchain action. 
That flow is too complex for many first-time users and likely causes meaningful drop-off before users ever reach their first lock. 

The proposed solution is to introduce a frictionless onboarding flow using Wallet-as-a-Service and integrated on-ramping, 
so a user can go from landing on a pool page to funding and locking into a pool through a familiar checkout-like experience.

This does not only apply to Revenue Pools. 
The same infrastructure can later support Portal usage payments and other Web2-to-Web3 payment flows inside the SQD ecosystem. 

## Problem
### Current situation

The current user journey is too long and too technical for mainstream users.

A new participant typically has to:

1. Understand what SQD and Revenue Pools are.
2. Install or connect a browser wallet.
3. Buy SQD or buy another asset first.
4. Ensure funds are on the correct network.
5. Potentially bridge assets to Arbitrum.
6. Connect the wallet to the app.
7. Approve and lock SQD into the pool.

This means users face multiple friction points before they experience any product value.

## Why this matters

Revenue Pools are not just a community feature.
If users drop before funding or locking, We lose:
- perceived product momentum
- conversion from interest to actual locked capital

## Proposed solution

Introduce a frictionless onboarding and payment flow using:

- **Wallet-as-a-Service**
- **embedded wallet creation**
- **Apple Pay / card on-ramp**
- **one-click or near-one-click lock into a Revenue Pool**

### Target user flow

1. User lands on a Revenue Pool page.
2. User signs up with email, Google, or Apple.
3. Wallet is created automatically in the background.
4. User funds via Apple Pay or card.
5. Funds are routed to the correct chain and asset path.
6. User confirms and becomes an active pool participant.

The key principle is simple: the user should reach their **first lock** before needing to learn wallet infrastructure.

## Market examples
### Moonshot
Moonshot is one of the clearest examples of a crypto product using a familiar payment experience to reduce onboarding friction. 
Its product messaging emphasizes that users can convert cash to crypto quickly, and its App Store listing shows 2M+ users. 

More importantly, Coinbase published a dedicated [Moonshot case study](https://www.coinbase.com/developer-platform/discover/case-studies/moonshot) stating that Moonshot **increased onramp conversion by over 25%** using Coinbase Onramp API. 

Coinbase also says Moonshot users could onboard funds **approximately 40% faster** with the new flow. 

**Why this matters for SQD:** it proves that a mainstream-feeling fiat-to-crypto flow can meaningfully reduce the psychological and operational barrier to first onchain action. 

### pump.fun

[Privy’s pump.fun case study](https://privy.io/blog/token-creation-for-everyone-with-pump-fun) reports that since integrating Privy for wallet infrastructure, pump.fun has seen:

- 2.5 million self-custodial wallets provisioned via Privy
- 8.5 million transactions since embedded wallets became the default

**Why this matters for SQD:** when wallets become invisible and automatic, products can scale onboarding dramatically.


## Expected value
- Baymard reports that 19% of checkout abandonment comes from forced account creation, 18% from a long or complicated checkout, and 10% from not having enough preferred payment methods. 
- Stripe reported that showing at least one additional relevant payment method increased conversion by 7.4% on average and revenue by 12%; 
Apple Pay alone delivered an average 22.3% conversion uplift and 22.5% revenue uplift in Stripe’s study. 
- Apple states that making Apple Pay prominent and default reduces abandonment and increases conversion. 

- **Baymard cart abandonment data**: [Baymard — Cart Abandonment Rate Statistics](https://baymard.com/lists/cart-abandonment-rate)
- **Baymard checkout usability research**: [Baymard — Checkout Usability Research](https://baymard.com/research/checkout-usability)
- **Stripe payment method conversion study**: [Stripe — Testing the conversion impact of 50+ global payment methods](https://stripe.com/blog/testing-the-conversion-impact-of-50-plus-global-payment-methods)
- **Apple Pay conversion guidance**: [Apple Developer — Apple Pay Overview](https://developer.apple.com/apple-pay/)

Because the current SQD participation journey is more complex than a typical ecommerce checkout, these benchmarks should be treated as a conservative floor, not a ceiling.

<img width="1600" height="967" alt="image" src="https://github.com/user-attachments/assets/70dd842e-dbb4-4db5-ba51-9af6cce009a1" />


## One-line takeaway

**Portal Pools do not need better wallet education first; they need a flow where users can reach their first lock before infrastructure friction makes them drop.**
