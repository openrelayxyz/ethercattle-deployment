Implementation
==============

In `go-ethereum/internal/ethapi/backend.go`, a Backend interface is specified.
Objects filling this interface can be passed to ethapi.GetAPIS() to return
`[]rpc.API`, which can be used to serve the Ethereum RPC APIs. Presently there
are two implementations of the Backend interface, one for full Ethereum nodes
and one for Light Ethereum nodes that depend on the LES protocol.

This project will implement a third backend implementation, which will provide
the necessary information to ethapi.GetAPIs() to in turn provide the RPC APIs.

Backend Functions To Implement
------------------------------

This section explores each of the 26 methods required by the Backend interface.
This is an initial pass, and attempts to implement these methods may prove more
difficult than described below.

Downloader()
............

Downloader must return a `*go-ethereum/eth/downloader.Downloader` object.
Normally the `Downloader` object is responsible for managing relationships with
remote peers, and synchronizing the block from remote peers. As our replicas
will receive data directly via Kafka, the Downloader object won't see much use.
Even so, the `PublicEthereumAPI` struct expects to be able to retrieve a
`Downloader` object so that it can provide the `eth_syncing` API call.

If the Backend interface required an interface for a downloader rather than a
specific Downloader object, we could stub out at Downloader that provided the
`eth_syncing` data based on the current Kafka sync state. Unfortunately the
Downloader requires a specific object constructed with the following
properties:

* `mode SyncMode` - An integer indicating whether the SyncMode is Fast, Full, or Light. We can probably specify "light" for our purposes.
* `stateDb ethdb.Database` - An interface to LevelDB. Our backend will neeed a Database instance, so this should be easy.
* `mux *event.TypeMux` - Used only for syncing with peers. If we avoid calling Downloader.Synchronize(), it appears this can safely be nil.
* `chain BlockChain` - An object providing the downloader.BlockChain interface. If we only need to support Downloader.Progress(), and we set SyncMode to LightSync, this can be nil.
* `lightchain LightChain` - An object providing the downloader.LightChain interface. If we only need to support Downloader.Progress(), and we set SyncMode to LightSync, we will need to stub this out and provide CurrentHeader() with the correct blocknumber.
* `dropPeer peerDropFn` - Only used when syncing with peers. If we avoid calling Downloader.Synchronize(), this can be `func(string) {}`

Constructing a `Downloader` with the preceding arguments should provide the
capabilities we need to offer the `eth_progress` RPC call.

ProtocolVersion()
.................

This just needs to return an integer indicating the protocol version. This
tells us what version of the peer-to-peer protocol the Ethereum client is
using. As replicas will not use a peer-to-peer protocol, it might make sense
for this to be a value like `-1`.

SuggestPrice()
..............

Should return a `big.Int` gas price for a transaction. This can use
`*go-ethereum/eth/gasprice.Oracle` to provide the same values a stanard
Ethereum node would provide. Note, however, that gasprice.Oracle requires a
Backend object of its own, so implementing SuggestPrice() will need to wait
until the following backend methods have been implemented:

* `HeaderByNumber()`
* `BlockByNumber()`
* `ChainConfig()`

ChainDb()
.........

Our backend will need to be constructed with an `ethdb.Database` object, which
will be it's primary source for much of the information about the blockchain
and state. This method will return that object.

For replicas, it might be prudent to have a wrapper that provides the
`ethdb.Database` interface, but errors on any write operations, as we want to
ensure that all write operations to the primary database come from the
replication process.

EventMux()
..........

This seem to be used by peer-to-peer systems. I can't find anything in the RPC
system that depends on `EventMux()`, so I think we can return `nil` for the
Replica backend.

AccountManager()
................

This returns an `*accounts.Manager` object, which manages access to Ethereum
wallets and other secret data. This would be used by the Private Ethereum APIs,
which our Replicas will not implement. Services that need to manage accounts in
conjunction with replica RPC nodes should utilize client side account managers
such as `Web3 Provider Engine <https://www.npmjs.com/package/web3-provider-engine>`_.

In a future phase we may decide to implement an AccountManager service for
replica nodes, but this would require serious consideration for how to securely
store credentials and share them across the replicas in a cluster.

SetHead()
.........

This is used by the private debug APIs, allowing developers to set the
blockchain back to an earlier state in private environments. Replicas should
not be able to roll back the blockchain to an earlier state, so this method
should be a no-op.

HeaderByNumber()
................

HeaderByNumber needs to return a `*core/types.Header` object corresponding to
the specified block number. This will need to get information from the
database. It might be possible to leverage in-memory caches to speed up these
data lookups, but it must not rely on information normally provided by the
peer-to-peer protocol manager.

This should be able to use `core.GetCanonicalHash()` to get the blockhash, then
`core.GetHeader()` to get the Block Number.

BlockByNumber()
...............

BlockByNumber needs to return a `*core/types.Block` object corresponding to the
specified block number. This will need to get information from the
database. It might be possible to leverage in-memory caches to speed up these
data lookups, but it must not rely on information normally provided by the
peer-to-peer protocol manager.

This should be able to use `core.GetCanonicalHash()` to get the blockhash, then
`core.GetBlock()` to get the Block Number.

StateAndHeaderByNumber()
........................

Needs to return a `*core/state.StateDB` object and a `*core/types.Header`
object corresponding to the specified block number.

The header can be retrieved with `backend.HeaderByNumber()`. Then the stateDB
object can be created with `core/state.New()` given the hash from the retrieved
header and the ethdb.Database.

GetBlock()
..........

Needs to return a `*core/types.Block` given a `common.Hash`. This should be
able to use `core.GetBlockNumber()` to get the block number for the hash, and
`core.GetBlock()` to retrieve the `*core/types.Block`.

GetReceipts()
.............

Needs to return a `core/types.Receipts` given a `common.Hash`. This should be
able to use `core.GetBlockNumber()` to get the block number for the hash, and
`core.GetBlockReceipts()` to retrieve the `core/types.Receipts`.

GetTd()
.......

Needs to return a `*big.Int` given a `common.Hash`. This should be able to use
`core.GetBlockNumber()` to get the block number for the hash, and
`core.GetTd()` to retrieve the total difficulty.

GetEVM()
........

Needs to return a `*core/vm.EVM`.

This requires a `core.ChainContext` object, which in turn needs to implement:

* `Engine()` - A conensus engine instance. This should reflect the conensus
  engine of the server the replica is replicating. This would be Ethash for
  Mainnet, but may be Clique or eventually Casper for other networks.
* `GetHeader()` - Can proxy `backend.GetHeader()`

Beyond the construction of a new `ChainContext`, this should be comparable to
the implementation of eth/api_backend.go's `GetEVM()`

.. _event-apis:

Subscribe Event APIs
....................

The following methods exist as part of the Event Filtering system.

* `SubscribeChainEvent()`
* `SubscribeChainHeadEvent()`
* `SubscribeChainSideEvent()`
* `SubscribeTxPreEvent()`

As discussed in :ref:`load-balancing`, the initial implementation of the replica
service will not support the filtering APIs. As such, these methods can be
no-ops that simply return `nil`. In the future we may implement these methods,
but it will need to be a completely new implementation to support filtering on
the cluster instead of individual replicas.

.. _send-tx:

SendTx()
........

As replica nodes will not have peer-to-peer connections, they will not be able
to send transactions to the network via conventional methods. Instead, we
propose that the replica will simply queue transactions onto a Kafka topic.
Independent from the replica service we can have consumers of the transaction
topic emit the transactions to the network using different methods. The scope
of implementing `SendTx()` is limited to placing the transaction onto a Kafka
topic. Processing those events and emitting them to the network will be
discused in :ref:`tx-emitters`.

Transaction Pool Methods
........................

The transaction pool in Go Ethereum is kept in memory, rather than in the
LevelDB database. This means that the primary log stream will not include
information about information about unconfirmed transactions. Additionally, the
primary APIs that would make use of the transaction pool are the filtering
transactions, which we established in :ref:`event-apis` will not be supported
in the initial implementation.

For the first phase, this project will not implement the transaction pool. In a
future phase, depending on demand, we may create a separate log stream for
transaction pool data. For the first phase, these methods will return as
follows:

* GetPoolTransactions() - Return an empty `types.Transactions` slice.
* GetPoolTransaction() - Return nil
* GetPoolNonce() - Use `statedb.GetNonce` to return the most recent confirmed
  nonce.
* Stats() - Return 0 transactions pending, 0 transactions queued
* TxPoolContent() - Return empty `map[common.Address]types.Transactions` maps
  for both pending and queued transactions.


ChainConfig()
.............

The ChainConfig property will likely be provided to the Replica Backend as the
backend is contructed, so this will return that value.

CurrentBlock()
..............

This will need to look up the block hash of the latest block from LevelDB,
then use that to invoke `backend.GetBlock()` to retrieve the current block.

In the future we may be able to optimize this method by keeping the current
block in memory. If we track when the `LatestBlock` key in LevelDB gets
updated, we can clear the in-memory cache as updates come in.

.. _tx-emitters:

Transaction Emitters
--------------------

Emitting transactions to the network is a different challenge than replicating
the chain for reading, and has different security concerns. As discussed in
:ref:`send-tx`, replica nodes will not have peer-to-peer connections for the
purpose of broadcasting transactions. Instead, when the `SendTx()` method is
called on our backend, it will log the transaction to a Kafka topic for a
downstream Transaction Emitter to handle.

Different use cases may have different needs from transaction emitters. On one
end of the spectrum, OpenRelay needs replicas strictly for watching for order
fills and checking token balances, so no transaction emitters are necessary in
the current workflow. Other applications may have high volumes of transactions
that need to be emitted.

The basic transaction emitter will watch the Kafka topic for transactions, and
make RPC calls to transmit those messages. This leaves organizations with
several options for how to transmit those messages to the network.
Organizations may choose to:

* Not to run a transaction emitter at all, if their workflows do not generate transactions.
* Run a transaction emitter pointed to the source server that is feeding their replica nodes.
* Run a transaction emitter pointed to a public RPC server such as Infura.
* Run a separate cluster of light nodes for transmitting transactions to the network

Security Considerations
.......................

The security concerns relating to emitting transactions are different than the
concerns for read operations. One reason for running a private cluster of RPC
nodes is that the RPC protocol doesn't enable publicly hosted nodes to prove
the authenticity of the data they are serving. To have a trusted source of
state data an organization must have trusted Ethereum nodes. When it comes to
emitting transactions, the peer-to-peer protocol offers roughly the same
assurances that transactions will be emitted to the network as RPC nodes. Thus,
some organizations may decide to transmit transactions through APIs like Infura
and Etherscan even though they choose not to trust those services for state
data.
