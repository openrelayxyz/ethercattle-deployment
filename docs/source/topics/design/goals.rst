.. _design-goals:

Design Goals
============

The primary goal of the Ether Cattle intiative is to provide access to Ethereum
RPC services with minimal operational complexity and cost. Ideally this will
be achieved by enhancing an existing Ethereum client with capabilities that
simplify the operational challenges.

Health Checks
-------------

A major challenge with existing Ethereum nodes is evaluating the health of an
individual node. Generally nodes should be considered healthy if they have the
blockchain and state trie at the highest block, and are able to serve RPC
requests relating to that state. If a node is more than a couple of blocks
behind the network, it should be considered unhealthy.

.. _initialization:

Service Initialization
----------------------

One of the major challenges with treating Ethereum nodes as disposable is the
initialization time. Conventionally a new instance must find peers, download
the latest blocks from those peers, and validate each transaction in those
blocks. Even if the instance is built from a relatively recent snapshot, this
can be a bandwidth intensive, computationally intensive, disk intensive, and
time consuming process.

In a trustless peer-to-peer system, these steps are unavoidable. Malicious
peers could provide incorrect information, so it is necessary to validate all
of the information received from untrusted peers. But given several nodes
managed by the same operator, it is generally safe for those nodes to trust
each other, allowing individual nodes to avoid some of the computationally
intensive and disk intensive steps that make the initialization process time
consuming.

Ideally node snapshots will be taken periodically, new instances will launch
based on the most recent available snapshot, and then sync the blockchain and
state trie from trusted peers without having to validate every successive
transaction. Assuming relatively recent snapshots are available, this should
allow new instances to start up in a matter of minutes rather than hours.

Additionally, during the initialization process services should be identifiable
as still initializing and excluded from the load balancer pool. This will
avoid nodes serving outdated information during initialization.

.. _load-balancing:

Load Balancing
--------------

Given reliable healthchecks and a quick initialization process, one challenge
remains on loadbalancing. The Ethereum RPC protocol supports a concept of
"filter subscriptions" where a filter is installed on an Ethereum node and
subsequent requests about the subscription are served updates about changes
matching the filter since the previous request. This requires a stateful
session, which depends on having a single Ethereum node serve each successive
request relating to a specific subscription.

For now this can be addressed on the client application using `Provider Engine's Filter Subprovider <https://github.com/MetaMask/provider-engine/blob/master/subproviders/filters.js>`_.
The Filter Subprovider mimics the functionality of installing a filter on a
node and requesting updates about the subscription by making a series of
stateless calls against the RPC server. Over the long term it might be
beneficial to add a shared database that would allow the load balanced RPC
nodes to manage filters on the server side instead of the client side, but due
to the existence of the Filter Subprovider that is not necessary in the short
term.

Reduced Computational Requirements
----------------------------------

As discussed in :ref:`initialization`, a collection of nodes managed by a
single operator do not have the same trust model amongst themselves as nodes in
a fully peer-to-peer system. RPC Nodes can potentially decrease their
computational overhead by relying on a subset of the nodes within a group to
validate transactions. This would mean that a small portion of nodes would need
the computational capacity to validate every transaction, while the remaining
nodes would have lower resource requirements to serve RPC requests, allowing
flexible scaling and redundancy.
