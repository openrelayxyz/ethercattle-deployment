Operational Requirements
========================

The implementation discussed in previous sections relates directly to the
software changes required to help operationalize Ethereum clients. There are
also ongoing operational processes that will be required to maintain a cluster
of master / replica nodes.

.. _cluster-initialization:

Cluster Initialization
----------------------

Initializing a cluster comprised of a master and one or more replicas requires
a few steps.

Master initialization
.....................

Before standing up any replicas or configuring the master to send logs to
Kafka, the master should be synced with the blockchain. In most circumstances,
this should be a typical Geth fast sync with standard garbage collection
arguments.


.. _leveldb-snapshots:
LevelDB Snapshotting
....................

Once the master is synced, the LevelDB directory needs to be snapshotted. This
will become the basis of both the subsequent master and the replica servers.

Replication Master Configuration
................................

Once synced and ready for replication, the master needs to be started with the
garbage collection mode of "archive". Without the "archive" garbage collection
mode, the state trie is kept in memory, and not written to either LevelDB or
Kafka immediately. If state data is not written to Kafka immediately, the
replicas have only the chain data and cannot do state lookups. The master
should also be configured with a Kafka broker and topic for logging write
operations.

Replica Configuration
......................

Replicas should be created with a copy of the LevelDB database snapshotted in
:ref:`leveldb-snapshots`. When executed, the replica service should be pointed
to the same Kafka broker and topic as the master. Any changes written by the
master since the LevelDB snapshot will be pulled from Kafka before the Replica
starts serving HTTP requests.

Periodic Replica Snapshots
--------------------------

When new replicas are scaled up, they will connect to Kafka to pull any changes
not currently reflected in their local database. The software manages this by
storing the Kafka offset of each write operation as it persists to LevelDB, and
when a new replica starts up it will replay any write operations more recent
than the offset of the last saved operation. However this assumes that Kafka
will have the data to resume from that offset, and in practice Kafka
periodically discards old data. Without intervention, a new replica will
eventually spin up to find that Kafka no longer has the data required for it to
resume.

The solution for this is fairly simple. We need to snapshot the replicas more
frequently than Kafka fully cycles out data. Each snapshot should reflect the
latest data in Kafka at the time the snapshot was taken, and any new replicas
created from that snapshot will be able to resume so long as Kafka still has
the offset from the time the snapshot was taken.

The mechanisms for taking snapshots will depend on operational infrastructure.
The implementation will vary between cloud providers or on-premises
infrastructure management tools, and will be up to each team to implement
(though we may provide additional documentation and tooling for specific
providers).

Administrators should be aware of Kafka's retention period, and be sure that
snapshots are taken more frequently than the retention period, leaving enough
time to troubleshoot failed snapshots before Kafka runs out

Periodic Cluster Refreshes
--------------------------

Because replication requires the master to write to LevelDB with a garbage
collection mode of "archive", the disk usage for each node of a cluster can
grow fairly significantly after the initial sync. When disk usage begins to
become a problem, the entire cluster can be refreshed following the
:ref:`cluster-initialization` process.

Both clusters can run concurrently while the second cluster is brought up, but
it is important that the two clusters use separate LevelDB snapshots and
separate Kafka partitions to stay in sync (they can use the same Kafka broker,
if it is capable of handling the traffic).

As replicas for the new cluster are spun up, they will only start serving HTTP
requests once they are synced with their respective Kafka partition. Assuming
your load balancer only attempts to route requests to a service once it has
passed health checks, both clusters can co-exist behind the load balancer
concurrently.


Multiple Clusters
-----------------

Just as multiple clusters can co-exist during a refresh, multiple clusters can
co-exist for stability purposes. Within a single cluster, the master server is
a single point of failure. If the master gets disconnected from its peers or
fails for other reasons, its peers will not get updates and become stale. A new
master can be created from the last LevelDB snapshot, but that will take time
during which the replicas will be stale.

With multiple clusters, when a master is determined to be unhealthy its
replicas could be removed from the load balancer to avoid stale data, and
additional clusters could continue to serve current data.

High Availability
-----------------

A single Ether Cattle cluster provides several operational benefits over running
conventional Ethereum nodes, but the master server is still a single point of
failure. Using data stored in Kafka, the master can recover much more quickly
than a node that needed to sync from peers, but that can still lead to a period
of time where the replicas are serving stale data.

To achieve high availability requires multiple clusters with independent masters
and their own replicas. Multiple replica clusters can share a high-availability
Kafka cluster. The following formula can be used to determine the statistical
availability of a cluster:

.. math:: a = 1 - (1 - \frac{mtbf}{mttr + mtbf})^N

Where:

* `mtbf` - Mean Time Between Failures - The average amount of time between failures of a master server
* `mttr` - Mean Time To Recovery - The average amount of time it takes to replace a master server after a failure
* `N` - The number of independently operating clusters

The values of `mtbf` and `mttr` will depend on your operational environment.
With our AWS CloudFormation templates, we have established an `mttr` of 45
minutes when snapshotting daily. We have not gathered enough data to establish a
mtbf, but with two independent clusters and a 45 minute `mttr`, EC2's regional
SLA becomes the bounding factor of availability if the `mtbf` is greater than
two weeks.

This formula focuses only on the availability of masters - it assumes that each
master has multiple independent replicas. If a master only has a single replica,
that will hurt the `mtbf` of the cluster as a whole.
