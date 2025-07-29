#!/usr/bin/env bash
# setup_cluster.sh
#
# Generic KIND‑based cluster bootstrapper for the network‑experimentation repo.
# Handles:
#   • Submariner   – control & managed clusters (prefix: sub-)
#   • L2SM         – control & managed clusters (prefix: l2sm-)
#
# Features:
#   • Auto‑creates ./<project>/<cluster_name>/experiment-<N> (+CREATED_AT)
#   • Renders KIND config from common/templates/cluster.yaml.template via envsubst
#   • Starts Prometheus (Submariner only)
#   • Installs cert‑manager + Multus automatically for L2SM managed clusters
#
# Usage examples
#   # Submariner control plane (experiment auto‑increment)
#   ./setup_cluster.sh submariner control
#
#   # Submariner managed cluster, explicit experiment 5 & custom API IP
#   API_IP=192.168.1.50 ./setup_cluster.sh submariner managed-1 5
#
#   # L2SM control plane (experiment auto‑increment)
#   ./setup_cluster.sh l2sm control
#
#   # L2SM managed cluster (auto‑increment; installs cert‑manager + Multus)
#   ./setup_cluster.sh l2sm managed-1
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------------------------------------------------------------------
# Input arguments & sanity checks
# ---------------------------------------------------------------------------
PROJECT=${1:-submariner}          # submariner | l2sm
CLUSTER_NAME=${2:-control}       # control | managed-<n>

case "${PROJECT}" in
  submariner) DOCKER_PREFIX="sub-" ;;
  l2sm)       DOCKER_PREFIX="l2sm-" ;;
  *)
    echo "[ERROR] Unknown project '${PROJECT}'. Expected 'submariner' or 'l2sm'." >&2
    exit 1
    ;;
esac

# Full logical name that appears inside KIND config & Docker nodes
CLUSTER_FULL_NAME="${DOCKER_PREFIX}${CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# Directory layout & experiment auto‑increment
# ---------------------------------------------------------------------------
BASE_DIR="$(pwd)/${PROJECT}/${CLUSTER_NAME}"
mkdir -p "${BASE_DIR}"



# ---------------------------------------------------------------------------
# KIND config generation from template
# ---------------------------------------------------------------------------
TEMPLATE_PATH="$(pwd)/common/templates/cluster.yaml.template"
if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "[ERROR] KIND template not found at ${TEMPLATE_PATH}" >&2
  exit 1
fi

# Resolve API_IP: use env if provided, else best‑effort gateway detection or fallback 127.0.0.1
if [[ -z "${API_IP:-}" ]]; then
  API_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
  API_IP="${API_IP:-127.0.0.1}"
fi

export NAME="${CLUSTER_FULL_NAME}" API_IP

envsubst < "${TEMPLATE_PATH}" > "${BASE_DIR}/cluster.yaml"

echo "\n--- CLUSTER BOOTSTRAP SUMMARY ---"
echo "Project          : ${PROJECT}"
echo "Cluster name     : ${CLUSTER_NAME} (full: ${CLUSTER_FULL_NAME})"
echo "Docker prefix    : ${DOCKER_PREFIX}"
echo "API IP           : ${API_IP}"
echo "Base directory   : ${BASE_DIR}"
echo "KIND config path : ${BASE_DIR}/cluster.yaml"
echo "--------------------------------\n"

KUBECONFIG="${BASE_DIR}/kubeconfig"

# ---------------------------------------------------------------------------
# KIND cluster creation
# ---------------------------------------------------------------------------
kind create cluster --kubeconfig "${KUBECONFIG}" --config "${BASE_DIR}/cluster.yaml"

# ---------------------------------------------------------------------------
# CNI plugins (Flannel + generic plugins)
# ---------------------------------------------------------------------------
wget -q https://github.com/containernetworking/plugins/releases/download/v1.6.0/cni-plugins-linux-amd64-v1.6.0.tgz
mkdir -p plugins/bin
tar -xf cni-plugins-linux-amd64-v1.6.0.tgz -C plugins/bin
rm cni-plugins-linux-amd64-v1.6.0.tgz

for NODE in control-plane worker worker2; do
  FULL_NODE="${CLUSTER_FULL_NAME}-${NODE}"
  docker cp ./plugins/bin/. "${FULL_NODE}:/opt/cni/bin"
  docker exec -it "${FULL_NODE}" modprobe br_netfilter
  docker exec -it "${FULL_NODE}" sysctl -p /etc/sysctl.conf
done

# Deploy flannel
kubectl --kubeconfig "${KUBECONFIG}" apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
kubectl --kubeconfig "${KUBECONFIG}" wait --for=condition=Ready pods -n kube-flannel -l app=flannel --timeout=300s

# ---------------------------------------------------------------------------
# Extra components for L2SM managed clusters
# ---------------------------------------------------------------------------
if [[ "${PROJECT}" == "l2sm" && "${CLUSTER_NAME}" != "control" ]]; then
  echo "Installing cert‑manager & Multus (L2SM managed cluster)..."
  kubectl --kubeconfig "${KUBECONFIG}" apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
  kubectl --kubeconfig "${KUBECONFIG}" apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
fi

# ---------------------------------------------------------------------------
# Prometheus -- It's used by both experiments but we only want to deploy once
# ---------------------------------------------------------------------------
if [[ "${PROJECT}" == "submariner" ]]; then
  docker compose -f "$(pwd)/common/prometheus/docker-compose.yml" up -d
fi
