#!/bin/bash

DIRECTORY=$(pwd)/l2sm

# First we install the multi domain client
git clone https://github.com/Networks-it-uc3m/l2sm-md.git
kubectl --kubeconfig $(DIRECTORY)/control/kubeconfig apply -f https://github.com/Networks-it-uc3m/l2sm-md/raw/refs/heads/development/deployments/l2smmd-deployment.yaml

make -C $DIRECTORY/l2sm-md/ build
kubectl --kubeconfig $(DIRECTORY)/managed-1/kubeconfig config view -o jsonpath='{.cluster.certificate-authority-data}' --raw | base64 -d > $DIRECTORY/managed-1/cluster.key
$DIRECTORY/l2sm-md/bin/apply-cert --namespace l2sm-system --kubeconfig $(DIRECTORY)/control/kubeconfig --clustername  l2sm-managed-1 $DIRECTORY/managed-1/cluster.key

kubectl  --kubeconfig $(DIRECTORY)/managed-2/kubeconfig config view -o jsonpath='{.cluster.certificate-authority-data}' --raw | base64 -d > $DIRECTORY/managed-2/cluster.key
$DIRECTORY/l2sm-md/bin/apply-cert --namespace l2sm-system --kubeconfig $(DIRECTORY)/control/kubeconfig --clustername  l2sm-managed-2 $DIRECTORY/managed-2/cluster.key

# Then install l2sm in the managed clusters

kubectl --kubeconfig $(DIRECTORY)/managed-1/kubeconfig apply -f https://github.com/Networks-it-uc3m/L2S-M/raw/refs/heads/development/deployments/l2sm-deployment.yaml
kubectl --kubeconfig $(DIRECTORY)/managed-2/kubeconfig apply -f https://github.com/Networks-it-uc3m/L2S-M/raw/refs/heads/development/deployments/l2sm-deployment.yaml
