#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
KUBECONFIG_PATH="local/configs/kubeconfig"
CTX1="sub-managed-1"
CTX2="sub-managed-2"
# Submariner cluster IDs (must match what `kubectl -n submariner-operator describe Gateway` shows)
CLUSTER1_ID="sub-managed-1"
CLUSTER2_ID="sub-managed-2"
NS="net-test"

export KUBECONFIG="${KUBECONFIG_PATH}"

need_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing binary: $1"; exit 1; }; }
need_bin kubectl
need_bin subctl

apply_to_ctx() {
  local CTX="$1"

  # Create namespace if needed
  kubectl --context "$CTX" get ns "$NS" >/dev/null 2>&1 || kubectl --context "$CTX" create ns "$NS"

  # Headless service (one A record per pod)
  cat <<'YAML' | kubectl --context "$CTX" -n "$NS" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: toolbox
  labels:
    app: toolbox
spec:
  clusterIP: None
  selector:
    app: toolbox
YAML

  # Two alpine pods with tools, via StatefulSet (stable pod names: toolbox-0, toolbox-1)
  cat <<'YAML' | kubectl --context "$CTX" -n "$NS" apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: toolbox
spec:
  serviceName: "toolbox"
  replicas: 2
  selector:
    matchLabels:
      app: toolbox
  template:
    metadata:
      labels:
        app: toolbox
    spec:
      terminationGracePeriodSeconds: 0
      containers:
      - name: alpine
        image: alpine:3.20
        command: ["/bin/sh","-lc"]
        args:
          - |
            apk add --no-cache tcpdump iproute2 iputils bind-tools >/dev/null 2>&1 || exit 1;
            echo "Tools installed: $(tcpdump --version 2>/dev/null | head -1 || true)";
            sleep infinity
        securityContext:
          capabilities:
            add: ["NET_ADMIN","NET_RAW"]
YAML

  # Wait for pods to be ready
  kubectl --context "$CTX" -n "$NS" rollout status statefulset/toolbox --timeout=120s
}

echo ">>> Applying to $CTX1"
apply_to_ctx "$CTX1"
echo ">>> Applying to $CTX2"
apply_to_ctx "$CTX2"

# Export the headless service in both clusters so pods become discoverable via clusterset.local
echo ">>> Exporting service 'toolbox' to the clusterset"
subctl --context "$CTX1" export service --namespace "$NS" toolbox || true
subctl --context "$CTX2" export service --namespace "$NS" toolbox || true

echo
echo "=== Deployed ==="
for CTX in "$CTX1" "$CTX2"; do
  echo "--- $CTX"
  kubectl --context "$CTX" -n "$NS" get pods -o wide
done

echo
echo "=== How to ping across clusters ==="
echo "Example: from $CTX1 -> ping toolbox-0 in $CTX2"
echo "kubectl --context $CTX1 -n $NS exec -it toolbox-0 -- sh -lc 'ping -c3 toolbox-0.${CLUSTER2_ID}.toolbox.${NS}.svc.clusterset.local'"
echo
echo "Example: from $CTX2 -> ping toolbox-1 in $CTX1"
echo "kubectl --context $CTX2 -n $NS exec -it toolbox-1 -- sh -lc 'ping -c3 toolbox-1.${CLUSTER1_ID}.toolbox.${NS}.svc.clusterset.local'"
echo
echo "Tip: show the FQDNs (requires Lighthouse DNS/Nodelocal forwarding set up):"
echo "kubectl --context $CTX2 -n $NS exec -it toolbox-0 -- sh -lc 'getent hosts toolbox-0.${CLUSTER1_ID}.toolbox.${NS}.svc.clusterset.local'"
echo
echo "Cleanup:"
echo "kubectl --context $CTX1 -n $NS delete statefulset toolbox service toolbox"
echo "kubectl --context $CTX2 -n $NS delete statefulset toolbox service toolbox"
echo "kubectl --context $CTX1 delete ns $NS || true"
echo "kubectl --context $CTX2 delete ns $NS || true"
