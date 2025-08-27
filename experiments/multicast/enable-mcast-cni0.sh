#!/usr/bin/env bash
# enable-mcast-cni0.sh
# Enables IGMP snooping + IGMP querier on cni0 via SSH on all listed nodes.

set -euo pipefail

# ---- Config ----
: "${SSH_USER:=ubuntu}"            # change if your SSH user is different
SSH_KEY_OPT=${SSH_KEY:+-i "$SSH_KEY"}  # export SSH_KEY=/path/to/key if needed
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5)

STATE_FILE="${1:-local/configs/terraform/terraform.tfstate}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found: $STATE_FILE" >&2
  return 1 2>/dev/null || exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "This script requires 'jq' to parse JSON." >&2
  return 1 2>/dev/null || exit 1
fi

# bash >= 4 is required for associative arrays
if [[ -z ${BASH_VERSINFO+x} || ${BASH_VERSINFO[0]} -lt 4 ]]; then
  echo "bash >= 4 is required (associative arrays). Current: ${BASH_VERSION:-unknown}" >&2
  return 1 2>/dev/null || exit 1
fi

# Make NODES available to the caller's shell (when sourced)
declare -gA NODES=()

# 1) Preferred path: outputs.cluster_ips.value
mapfile -t __pairs < <(jq -r '
  .outputs.cluster_ips.value? // empty
  | to_entries[]
  | [.key, .value.ip] | @tsv
' "$STATE_FILE") || true

# >>> populate the array <<<
for line in "${__pairs[@]}"; do
  IFS=$'\t' read -r name ip <<< "$line"
  [[ -n "$name" && -n "$ip" ]] || continue
  NODES["$name"]="$ip"
done

REMOTE_SCRIPT='
set -e
BR=cni0
if [ ! -d "/sys/class/net/cni0/bridge" ]; then
  echo "[WARN] Bridge cni0 not found on $(hostname) — skipping."
  exit 0
fi

# Use tee so the redirection runs as root.
echo 1 | sudo tee /sys/class/net/cni0/bridge/multicast_snooping >/dev/null
# Some kernels may lack the querier knob; dont fail if absent.
if [ -e /sys/class/net/cni0/bridge/multicast_querier ]; then
  echo 1 | sudo tee /sys/class/net/cni0/bridge/multicast_querier >/dev/null
fi

S=$(cat /sys/class/net/cni0/bridge/multicast_snooping 2>/dev/null || echo "N/A")
Q=$(cat /sys/class/net/cni0/bridge/multicast_querier 2>/dev/null || echo "N/A")
echo "[OK] $(hostname): cni0 multicast_snooping=$S, multicast_querier=$Q"
'

echo "== Enabling multicast snooping + querier on cni0 across nodes =="
for name in "${!NODES[@]}"; do
  ip=${NODES[$name]}
  echo "--- $name ($ip) ---"
  if ! ssh "${SSH_OPTS[@]}" $SSH_KEY_OPT "${SSH_USER}@${ip}" "bash -s" <<< "$REMOTE_SCRIPT"; then
    echo "[ERROR] $name ($ip): SSH or command failed" >&2
  fi
done
echo "== Done =="
