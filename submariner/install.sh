#!/bin/bash

DIRECTORY=$(pwd)/submariner

# First we install the broker
subctl deploy-broker --kubeconfig $(DIRECTORY)/control/kubeconfig

# Join the managed clusters

subctl join --kubeconfig $(DIRECTORY)/managed-1/kubeconfig broker-info.subm --clusterid sub-managed-1
subctl join --kubeconfig $(DIRECTORY)/managed-2/kubeconfig broker-info.subm --clusterid sub-managed-2
