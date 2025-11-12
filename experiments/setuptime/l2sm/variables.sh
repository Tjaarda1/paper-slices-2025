#!/usr/bin/env bash
# Shared config for L2SM setup-time experiments

### Kubernetes
export KCFG_A="local/configs/k8s/kubeconfig-l2sces-managed-1.yaml"   # cluster with "ping"
export KCFG_B="local/configs/k8s/kubeconfig-l2sces-managed-2.yaml"   # cluster with "pong"
export NS="l2sces-system"
export POD_PING="ping-st"
export POD_PONG="pong-st"
export NET_IF="net1"   # l2sces interface

### Workload assets / helpers
export GO_CREATE_CMD='(
  set -e
  cd ./local/bin/l2sm-md/
  go run ./test/ --test-network-create
)'
export PING_YAML="experiments/setuptime/l2sces/ping.yaml"
export PONG_YAML="experiments/setuptime/l2sces/pong.yaml"

### Controller / ONOS
# Set IDCO_IP to the controller host (with or without port). Examples:
source config.env
: "${IDCO_IP:?Set IDCO_IP to the ONOS controller IP}"
export ONOS_URL_BASE="http://${IDCO_IP}/onos/vnets/api"

# The network object used for this experiment (resource id)
export ONOS_NETWORK_ID="${ONOS_NETWORK_ID:-setup-time}"
export ONOS_NET_URL="${ONOS_URL_BASE}/${ONOS_NETWORK_ID}"
# Where to POST to recreate. If your API posts to a collection, set ONOS_POST_URL="$ONOS_URL_BASE"
export ONOS_POST_URL=$ONOS_URL_BASE
export ONOS_AUTH="${ONOS_AUTH:-karaf:karaf}"

### Probing parameters
export P_MS="${P_MS:-5}"        # probe period (ms). Error bound will be ± P_MS/2
export RUNS="${RUNS:-100}"      # number of trials
export OUT_DIR="${OUT_DIR:-experiments/setuptime/l2sces/captures}"
export OUT_CSV="${OUT_CSV:-$OUT_DIR/setup_time.csv}"

### L2SM IPs on $NET_IF (static addresses you assigned)
export PING_IP="${PING_IP:-192.168.1.2}"
export PONG_IP="${PONG_IP:-192.168.1.3}"
