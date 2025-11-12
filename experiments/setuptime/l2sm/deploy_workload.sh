#!/usr/bin/env bash
set -euo pipefail
echo hola
# Load variables
source "./experiments/setuptime/l2sm/variables.sh"
echo hola

# tiny helpers
grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
ylw(){ printf "\033[33m%s\033[0m\n" "$*"; }
req(){ command -v "$1" >/dev/null || { echo "Missing dependency: $1" >&2; exit 1; }; }

req kubectl

grn "[1/4] Creating/refreshing test network fabric (optional)…"
{ eval "$GO_CREATE_CMD" >/dev/null 2>&1 && grn "  ok"; } || ylw "  skipped/failed (continuing)"

grn "[2/4] Deploying ping/pong pods…"
kubectl --kubeconfig "$KCFG_A" -n "$NS" apply -f "$PING_YAML"
kubectl --kubeconfig "$KCFG_B" -n "$NS" apply -f "$PONG_YAML"

grn "[3/4] Waiting for pods to be Ready…"
kubectl --kubeconfig "$KCFG_A" -n "$NS" wait --for=condition=Ready pod/"$POD_PING" --timeout=180s
kubectl --kubeconfig "$KCFG_B" -n "$NS" wait --for=condition=Ready pod/"$POD_PONG" --timeout=180s

grn "[4/4] Installing tools in pods (tcpdump on pong, iputils on ping)…"
kubectl --kubeconfig "$KCFG_B" -n "$NS" exec "$POD_PONG" -- sh -lc 'apk add --no-cache tcpdump >/dev/null'
kubectl --kubeconfig "$KCFG_A" -n "$NS" exec "$POD_PING" -- sh -lc 'apk add --no-cache iputils >/dev/null || true'

grn "Done. Ready to run setup_time.sh"
