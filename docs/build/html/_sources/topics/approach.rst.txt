Approach
========

Change Data Capture
-------------------

After considering several different approaches to meet our :ref:`design-goals`,
we settled on a Change Data Capture approach (CDC). The idea is to hook into
the database interface on one node, capture all write operations, and write
them to a transaction log that can be replayed by other nodes.

Capturing Write Operations
..........................

In the Go Ethereum codebase, there is a `Database` interface which must support
the following operations:

* Put
* Get
* NewBatch
* Has
* Delete
* Close

and a Batch interface which must support the following operations:

* Put
* Write
* ValueSize

We have created a simple CDC wrapper, which proxies operations to the standard
databases supported by Go Ethereum, and records `Put`, `Delete`, and
`Batch.Write` operations through a `LogProducer` interface. At present, we have
implemented a `KafkaLogProducer` to record write operations to a Kafka topic.

The performance impact to the Go Ethereum server is minimal. The CDC wrapper is
light weight, proxying requests to the underlying database with minimal
overhead. Writing to the Kafka topic is handled asynchronously, so write
operations are unlikely to be delayed substantially due to logging. Read
operations be virtually unaffected by the wrapper.

While we have currently implemented a Kafka logger, we have defined an abstract
interface that could theoretically support a wide variety of messaging systems.

Replaying Write Operations
..........................

We also have a modified Go Ethereum service which uses a `LogConsumer`
interface to pull logs from Kafka and replay them into a local LevelDB
database. The index of the last written record is also recorded in the
database, allowing the service to resume in the event that it is restarted.

Preliminary Implementation
,,,,,,,,,,,,,,,,,,,,,,,,,,

In the current implementation we simply disable peer-to-peer connections on the
node and populate the database via Kafka logs. Other than that it functions as
a normal Go Ethereum node.

The RPC service in its current state is semi-functional. Many RPC functions
default to querying the state trie at the "latest" block. However, which block
is deemed to be the "latest" is normally determined by the peer-to-peer
service. When a new block comes in it is written to the database, but the hash
of the latest block is kept in memory. Without the peer-to-peer service running
the service believes that the "latest" block has not updated since the process
initialized and read the block out of the database. If RPC functions are called
speciying the target block, instead of implicitly asking for the latest block,
it will look for that information in the database and serve it correctly.

Despite preliminary successes, there are several potential problems with the
current approach. A normal Go Ethereum node, even one lacking peers, assumes
that it is responsible for maintaining its database. Occasionally this will
lead to replicas attempting to upgrade indexes or prune the state trie. This is
problematic because the same operations can be expected to come from the write
log of the source node. Thus we need an approach where we can ensure that the
read replicas will make no effort to write to their own database.

Proposed Implementation
,,,,,,,,,,,,,,,,,,,,,,,

Go Ethereum offers a standard `Backend` interface, which is used by the RPC
interface to retrieve the data needed to offer the standard RPC function calls.
Currently there are two main implementations of the standard Backend interface,
one for full Ethereum nodes, and one for light Ethereum nodes.

We propose to write a third implementation for replica Ethereum nodes. We
believe we can offer the core functionality required by RPC function calls
based entirely on the database state, without needing any of the standard
syncing capabilities.

Once that backend is developed, we can launch it as a separate service, which
will not attempt to do things like database upgrades, and which will not
attempt to establish peer-to-peer connections.

Under the hood, it will mostly leverage existing APIs for retrieving
information from the database. This should limit our exposure to changes in the
database breaking our code unexpectedly.

Other Models Considered
-----------------------

This section documents several other approaches we considered to achieving our
:ref:`design-goals`. This is not required reading for understanding subsequent
sections, but may help offer some context for the current design.

Higher Level Change Data Capture
................................

Rather than capturing data as it is written to the database, one option we
considered was capturing data as it was written to the State Trie, Blockchain,
and Transaction Pool. The advantage of this approach is that the change data
capture stream would be reflective of high level operations, and not dependent
on low level implementation details regarding how the data gets written to a
database. One disadvantage is that it would require more invasive changes to
consensus-critical parts of the codebase, creating more room for errors that
could effect the network as a whole. Additionally, because those changes would
have been made throughout the Go Ethereum codebase it would be harder to
maintain if Go Ethereum does not incorporate our changes. The proposed
implementation requires very few changes to core Go Ethereum codebase, and
primarily leverages APIs that should be relatively easy to maintain
compatibility with.

Shared Key Value Store
......................

Before deciding on a change-data-capture replication system, one option we
considered was to use a scalable key value store, which could be written to by
one Ethereum node and read by many. Some early prototypes were developed under
this model, but they all had significant performance limitations when it came
to validating blocks. The Ethereum State Trie requires several read operations
to retrieve a single piece of information. These read operations are practical
when made against a local disk, but latencies become prohibitively large when
the state trie is stored on a networked key value store on a remote system.
This made it infeasible for an Ethereum node to process transactions at the
speeds necessary to keep up with the network.

Extended Peer-To-Peer Model
...........................

One option we explored was to add an extended protocol on top of the standard
Ethereum peer-to-peer protocol, which would sync the blockchain and state trie
from a trusted list of peers without following the rigorous validation
procedures. This would have been a substantially more complex protocol than the
one we are proposing, and would have put additional strain on the other nodes
in the system.

Replica Codebase from Scratch
.............................

One option we considered was to use Change Data Capture to record change logs,
but write a new system from the ground-up to consume the captured information.
Part of the appeal of this approach was that we have developers interested in
contributing to the project who don't have a solid grasp of Go, and the replica
could have been developed in a language more accessible to our contributors.
The biggest problem with this approach, particularly with the low level CDC, is
that we would be tightly coupled to implementation details of how Go Ethereum
writes to LevelDB, without having a shared codebase for interpreting that data.
A minor change to how Go Ethereum stores data could break our replicas in
subtle ways that might not be caught until bad data was served in production.

In the proposed implementation we will depend not only on the underlying data
storage schema, but also the code Go Ethereum uses to interpret that data. If
Go Ethereum changes their schema *and* changes their code to match while
maintaining API compatibility, it should be transparent to the replicas. It is
also possible that Go Ethereum changes their APIs in a way that breaks
compatibility, but in that case we should find ourselves unable to compile the
replica without fixing the dependency, and shouldn't see surprises on a running
systme.

Finally, by building the replica service in Go as an extension to the existing
Go Ethereum codebase, there is a reasonable chance that we could get the
upstream Go Ethereum project to integrate our extensions. It is very unlikely
that they would integrate our read replica extensions if the read replica is a
separate project written in another language.
