#!/usr/bin/env python

"""
This script connects different masters controlled by the same organization.

When the script starts up, it sends its connectivity information to a Kafka
topic. It then follows the Kafka topic (from the earliest available records)
establishing all peers listed on the Kafka topic as trusted peers and attempting
to connect to them.
"""

import json
import kafka
import socket
import random
import time
import logging
from six.moves.urllib.parse import unquote_plus

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class IPCBackend(object):
    def __init__(self, path):
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(path)
            except socket.error:
                # Wait for socket to become avaialble
                pass
            else:
                break
    def get(self, method, params=None):
        if params is None:
            params = []
        id = random.randint(0, 4096)
        self.s.send(json.dumps({
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": id
        }).encode("utf8"))
        response = ""
        while True:
            response += self.s.recv(16192)
            try:
                res = json.loads(response)
            except ValueError:
                logger.warning("Unexpected JSON payload: '%s'", response)
                pass
            else:
                break
        if res["id"] != id:
            raise Exception("Got unexpected ID")
        return res


def trustedPeerManager(path, broker_config, topic):
    backend = IPCBackend(path)
    admin = kafka.KafkaAdminClient(**broker_config)
    try:
        # We can't rely on auto-creating the topic, because it will default to
        # snappy compression, which Python doesn't natively support and we
        # don't want to mess with setting up
        admin.create_topics([
            kafka.admin.NewTopic(topic, 1, 3,
                                 topic_configs={"compression.type": "gzip"})
        ])
    except kafka.errors.TopicAlreadyExistsError:
        pass
    consumer = kafka.KafkaConsumer(topic, auto_offset_reset='earliest', **broker_config)
    producer = kafka.KafkaProducer(**broker_config)
    myIp = socket.gethostbyname(socket.gethostname())
    node_info = backend.get("admin_nodeInfo")["result"]
    enode = node_info["enode"]
    internal_enode = "%s@%s:30303" % (enode.split("@")[0], myIp)
    producer.send(topic, internal_enode.encode("utf8"))
    logger.info("Registered with %s as %s", topic, internal_enode)
    registered = set([internal_enode])
    for msg in consumer:
        peer = msg.value.decode("utf8")
        if peer not in registered:
            backend.get("admin_addTrustedPeer", [peer])
            backend.get("admin_addPeer", [peer])
            logger.info("Added %s as trusted peer", peer)
        registered.add(peer)

def externalPeerManager(path):
    backend = IPCBackend(path)
    peers = {}
    while True:
        block_number = backend.get("eth_blockNumber")["result"]
        logger.info("blockNumber: %s" % int(block_number, 16))
        peer_list = backend.get("admin_peers")["result"]
        logger.info("peerCount: %s" % len(peer_list))
        try:
            max_difficulty = max(0, 0, *[
                p.get("protocols", {}).get("eth", {}).get("difficulty", 0)
                for p in peer_list
                if isinstance(p.get("protocols", {}).get("eth"), dict)
            ])
        except AttributeError:
            raise ValueError("Got %s" % peer_list)
        for peer in peer_list:
            enode = peer["enode"]
            try:
                peer_difficulty = peer["protocols"]["eth"]["difficulty"]
            except TypeError:
                peer_difficulty = 0
            clean_record = {"count": 0, "difficulty": peer_difficulty}
            peers.setdefault(enode, clean_record)
            if peer_difficulty < (max_difficulty * 0.9999):
                if peers[enode]["difficulty"] < peer_difficulty:
                    peers[enode] = clean_record
                else:
                    peers[enode]["count"] += 1
                if peers[enode]["count"] > 10:
                    if backend.get("admin_removePeer", [enode])["result"]:
                        logger.info(
                            "Dropped %s for lack of progress", enode)
                        del peers[enode]
                    else:
                        logger.info("Failed to remove peer: %s", enode)
        time.sleep(20)

if __name__ == "__main__":
    import argparse
    import multiprocessing
    parser = argparse.ArgumentParser()

    parser.add_argument("ipc_path")
    parser.add_argument("topic")
    parser.add_argument("broker_url")
    args = parser.parse_args()

    broker_config = {}
    try:
        credentials, resource = args.broker_url.split("@")
    except ValueError:
        resource = args.broker_url
    else:
        try:
            broker_config["sasl_plain_username"], password = credentials.split(":")
        except ValueError:
            broker_config["sasl_plain_username"] = credentials
        else:
            broker_config["sasl_plain_password"] = unquote_plus(password)
        broker_config["security_protocol"] = "SASL_PLAINTEXT"
        broker_config["sasl_mechanism"] = "PLAIN"
    try:
        hosts, tls = resource.split("?")
    except ValueError:
        broker_config["bootstrap_servers"] = resource.split(",")
    else:
        broker_config["bootstrap_servers"] = hosts.split(",")
        if tls == "tls=1":
            broker_config["security_protocol"] = "SASL_SSL"
    p1 = multiprocessing.Process(
        target=trustedPeerManager,
        args=(args.ipc_path, broker_config, args.topic)
    )
    p2 = multiprocessing.Process(
        target=externalPeerManager,
        args=(args.ipc_path,)
    )
    p1.start()
    p2.start()
    while True:
        if not p1.is_alive():
            p2.terminate()
            break
        if not p2.is_alive():
            p1.terminate()
            break
        time.sleep(0.1)
