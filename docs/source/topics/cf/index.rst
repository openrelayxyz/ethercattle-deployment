.. _cfn:

##################################
Running In AWS With CloudFormation
##################################

Introduction
============

The Ether Cattle Initiative has produced a set of CloudFormation templates for
those wishing to run a master / replica geth cluster on AWS. This document has
three sections. Section 1 is a simple walkthrough of how to deploy and manage a
cluster. Section 2 discusses the elements of the CloudFormation stack, and what
happens under the hood. Section 3 covers general troubleshooting of the cluster.

This document assumes a basic level of familiarity with AWS, and general systems
administration skills.

.. include::    ./setup.txt
.. include::    ./underthehood.txt
.. include::    ./troubleshooting.txt
