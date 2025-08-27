#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
LOCALCONFIG="$ROOT/local/configs"
K8S_DIR="$LOCALCONFIG/k8s"
SUBM_DIR="$LOCALCONFIG/submariner"
BROKER_INFO="$SUBM_DIR/broker-info.subm"

# Allow overriding subctl via env, default to 'subctl'
SUBCTL_BIN="${SUBCTL:-subctl}"

# Ensure dirs exist
mkdir -p "$SUBM_DIR"

# Basic sanity checks
: "${SUBCTL_BIN:?subctl binary not found/empty}"
command -v "$SUBCTL_BIN" >/dev/null 2>&1 || { echo "ERROR: '$SUBCTL_BIN' not in PATH"; exit 1; }

CONTROL_KC="$K8S_DIR/kubeconfig-sub-control.yaml"
M1_KC="$K8S_DIR/kubeconfig-sub-managed-1.yaml"
M2_KC="$K8S_DIR/kubeconfig-sub-managed-2.yaml"

for f in "$CONTROL_KC" "$M1_KC" "$M2_KC"; do
  [[ -f "$f" ]] || { echo "ERROR: kubeconfig not found: $f"; exit 1; }
done

echo "==> Deploying Submariner broker (control)"
# Run in SUBM_DIR so broker-info.subm lands there
(
  cd "$SUBM_DIR"
  "$SUBCTL_BIN" deploy-broker --kubeconfig "$CONTROL_KC"
)

echo "==> Joining managed-1 to broker"
"$SUBCTL_BIN" join \
  --kubeconfig "$M1_KC" \
  "$BROKER_INFO" \
  --clusterid sub-managed-1

echo "==> Joining managed-2 to broker"
"$SUBCTL_BIN" join \
  --kubeconfig "$M2_KC" \
  "$BROKER_INFO" \
  --clusterid sub-managed-2

echo "✓ Submariner broker deployed and clusters joined."
