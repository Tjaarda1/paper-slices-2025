#!/bin/bash

source config.env
DIRECTORY=$(pwd)/l2sm

MANAGED_1_BEARER_TOKEN=$(kubectl --kubeconfig ${DIRECTORY}/managed-1/kubeconfig create token -n l2sm-system l2sm-controller-manager --duration 1000h)
MANAGED_2_BEARER_TOKEN=$(kubectl --kubeconfig ${DIRECTORY}/managed-2/kubeconfig create token -n l2sm-system l2sm-controller-manager --duration 1000h)
MANAGED_1_API_KEY=$(kubectl  --kubeconfig $(DIRECTORY)/managed-1/kubeconfig config view -o jsonpath='{.cluster.server}' --raw)
MANAGED_2_API_KEY=$(kubectl  --kubeconfig $(DIRECTORY)/managed-2/kubeconfig config view -o jsonpath='{.cluster.server}' --raw)

envsubst < ${DIRECTORY}/slice-config.yaml.template > ${DIRECTORY}/slice-config.yaml

start=`date +%s`
go run $(DIRECTORY)/l2sm-md/test/ --config ${DIRECTORY}/slice-config.yaml --test-slice-create
end=`date +%s`

runtime=$((end-start))


