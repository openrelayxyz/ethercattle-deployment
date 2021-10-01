Introduction
============

There is a notion in Systems Administration that services are better when they
can be treated as Cattle, rather than Pets. That is to say, when cattle gets
badly injured its owner will typically discard it and replace it with
a new animal, but when a pet gets badly injured its owner will typically do
everything within reason to nurse the animal back to health. We want services
to be easily replaceable, and when a service begins to fail healthchecks we want
to discard it and replace it with a healthy instance.

For a service to be treated as cattle, it typically has the following
properties:

* It can be load-balanced, and any instance can serve any request as well as
  any other instance.
* It has simple health checks that can indicate when an instance should be
  removed from the load balancer pool.
* When a new instance is started it does not start serving requests until it
  is healthy.
* When a new instance is started it reaches a healthy state quickly.

Unfortunately, existing Ethereum nodes don't fit well into this model:

* Certain API calls are stateful, meaning the same instance must serve multiple
  successive requests and cannot be transparently replaced.
* There are numerous ways in which an Ethereum node can be unhealthy, some of
  which are difficult to determine.

  * A node might be unhealthy because it does not have any peers
  * A node might have peers, but still not receive new blocks
  * A node might be starting up, and have yet to reach a healthy state

* When a new instance is started it generally starts serving on RPC
  immediately, even though it has yet to sync the blockchain. If the load
  balancer serves request to this instance it will serve outdated information.
* When new instances are started, they must discover peers, download and
  validate blocks, and update the state trie. This takes hours under the best
  circumstances, and days under extenuating circumstances.

As a result it is often easier to spend time troubleshooting the problems on a
particular instance and get that instance healthy again, rather than replace it
with a fresh instance.

The goal of this initiative is to create enhanced open source tooling that will
enable DApp developers to treat their Ethereum nodes as replaceable cattle
rather than indespensable pets.

Publicly Hosted Ethereum RPC Nodes
----------------------------------

Many organizations are currently using publicly hosted Ethereum RPC nodes such
as Infura. While these services are very helpful, there are several reasons
organizations may not wish to depend on third party Ethereum RPC nodes.

First, the Ethereum RPC protocol does not provide enough information to
authenticate state data provided by the RPC node. This means that publicly
hosted nodes could serve inaccurate information with no way for the client to
know. This puts public RPC providers in a position where they could potentially
abuse their clients' trust for profit. It also makes them a target for hackers
who might wish to serve inaccurate state information.

Second, it means that a fundamental part of an organization's system depends on
a third party that offers no SLA. RPC hosts like Infura are generally available
on a best effort basis, but have been known to have significant outages. And
should Infura ever cease operations, consumers of their service would need to
rapidly find an alternative provider.

Hosting their own Ethereum nodes is the surest way for an organization to
address both of these concerns, but currently has significant operational
challenges. We intend to help address the operational challenges so that more
organizations can run their own Ethereum nodes.
