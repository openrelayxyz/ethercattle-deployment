# Ether Cattle Initiative

The Ether Cattle Initiative is a project to reduce the operational complexity of
managing Ethereum clients at the scale required of a dApp with lots of moving
parts (specifically OpenRelay).

We started with [Technical Design Documentation](https://ether-cattle-initiative.readthedocs.io/en/latest/topics/design/index.html),
applying the age-old database concepts of streaming replication to Ethereum
clients.

Then we built a [fork of Geth](https://github.com/notegio/go-ethereum) which
includes this streaming replication capability, as well as a replica service
that can be scaled to meet the highest demands of a dApp. It is also possible to
quickly replace a failed master with an already synced replica server in just a
few minutes, while recovering from even a day-old backup can take hours of
syncing from the Ethereum network.

Subsequently, wrote documentation for [how to run an Ether Cattle cluster](https://ether-cattle-initiative.readthedocs.io/en/latest/topics/metal/index.html)
on your own infrastructure.

Finally, we have developed a CloudFormation stack and [corresponding documentation](https://ether-cattle-initiative.readthedocs.io/en/latest/topics/cf/index.html)
that will deploy an Ether Cattle Cluster in AWS with relatively minimal human
interaction.

# FAQ

> Do you plan to keep this up-to-date with upstream Geth?

Yes. We periodically merge Geth's release tags back into our fork. We don't try
to keep up with the master branch, as we've found it sometimes gets a bit
unstable. Sometimes we might be one or two point releases behind, but we're in
this for the long haul, and eventually we'll need to add support for a new hard
fork, and we don't want to be too far behind when that happens. We only  touch
the core codebase in a few places, so these merges are usually pretty
straightforward.

> Do you plan to merge your changes back into Geth?

We're definitely open to the idea, 
