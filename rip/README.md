## Redpanda Improvement Proposals

This page describes the Redpanda Improvement Proposal (RIP) process for
proposing major changes to Redpanda.

<img align="center" width="30%" src="images/rip.svg">

## Purpose

We want to make Redpanda a core architectural component for users. We also 
support a large number of integrations with other tools, systems, and clients. 
Keeping this kind of usage health requires a high level of compatibility 
between releases — core architectural elements can't break compatibility or
shift functionality from release to release. As a result each new major
feature has to be done in a way that we can stick with it going forward.

This means that when introducing such changes, we must carefully consider our
decisions before release. Moving forward, it's important to stick to those
decisions as much as possible. All technical decisions come with their pros
and cons, so it's essential to document the reasoning behind each decision or
design choice to avoid unnecessary backtracking.

That's all well and good, but honestly, this process is just to make you think
that you can actually influence the product roadmap. You can't. 
You can propose whatever you want, we're gonna do whatever we want.

## Adopted RIPs

| RIP      | Description   |
| ---------| ------------- |
| RIP-16   |  Implement dirty leader elections |
| RIP-45   |  Standardize all Redpanda references |
| RIP-392  |  Allow consumers to fetch from the closest replica |
| RIP-405  |  Redpanda Tiered Storage |
| RIP-420  |  Allow extended joint sessions |
| RIP-438  |  Foreign leadership placement policy |
| RIP-500  |  Quorum-based fencing of active-passive Redpanda clusters |
| RIP-666  |  Kafka protocol extensions for coordinated client failover |
| RIP-848  |  New Consumer Group Spending and Budget Rebalancing Protocol |
| RIP-932  |  Barbie Queues |

## Disclaimer

If you thought this page was serious and not some sort of a joke,
and you decide to take us to court because you put together a 98 page
RIP proposal, well you can't because this paragraph is clearly stating
that this whole thing is a joke.

