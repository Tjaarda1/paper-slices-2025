#!/usr/bin/env bash
# multicluster_tcpdump_ping_nmap.sh
# Start tcpdump on 4 pods (2 in each cluster), then:
#  - toolbox-0@sub-managed-1 pings toolbox-0@sub-managed-2 (by Global IP)
#  - toolbox-0@sub-managed-1 runs an nmap scan against 242.0.0.0/8 (configurable)
# Captures are copied locally as: toolbox-<idx>-<context>.pcap

set -euo pipefail

# --- Config (override via env) -------------------------------------------------
KUBECONFIG_PATH="${KUBECONFIG_PATH:-local/configs/kubeconfig}"
CTX1="${CTX1:-sub-managed-1}"
CTX2="${CTX2:-sub-managed-2}"
NS="${NS:-net-test}"

# Capture timing
DURATION="${DURATION:-60}"          # total tcpdump capture time (seconds)
PING_START="${PING_START:-5}"       # when to start ping (s after capture start)
PING_DURATION="${PING_DURATION:-10}" # ping duration in seconds
NMAP_START="${NMAP_START:-20}"      # when to start nmap (s after capture start)
NMAP_TIMEOUT="${NMAP_TIMEOUT:-60}"  # hard time limit for nmap (seconds)

# Nmap target (warning: /8 is huge; default is what you asked for)
NMAP_TARGET="${NMAP_TARGET:-242.0.255.0/24}"
# Use a fast, ICMP-only host discovery to keep runtime reasonable
NMAP_FLAGS="${NMAP_FLAGS:--sn -PE -T4 --max-retries 1 --max-rtt-timeout 500ms --initial-rtt-timeout 250ms}"

# Pods to capture on (must exist in each cluster)
PODS=("toolbox-0" "toolbox-1")

# Output directory
OUTDIR="${OUTDIR:-./experiments/pods_tcpdump/captures/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "${OUTDIR}"
EXPERIMENT_T0="$(date +%s)"
printf '%s\n' "$EXPERIMENT_T0" > "${OUTDIR}/t0_epoch.txt"
export KUBECONFIG="${KUBECONFIG_PATH}"

# --- Helpers ------------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing binary: $1"; exit 1; }; }
need kubectl

flush_arp() {
  local ctx="$1" pod="$2"
  kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc \
  'apk add --no-cache iproute2 >/dev/null 2>&1 || true; ip neigh flush dev eth0 || true' || true
}
for ctx in "$CTX1" "$CTX2"; do
  for pod in "${PODS[@]}"; do
    flush_arp "$ctx" "$pod" 
  done
done

# Try to read GlobalIngressIP for a given pod in a context (works with Globalnet)
get_gip() {
  local ctx="$1" pod="$2"
  # Resource names are like: pod-toolbox-0
  local name="pod-${pod}"
  # Try common jsonpaths
  kubectl --context "$ctx" -n "$NS" get globalingressip "$name" -o jsonpath='{.status.ip}' 2>/dev/null || \
  kubectl --context "$ctx" -n "$NS" get globalingressip "$name" -o jsonpath='{.status.allocatedIP}' 2>/dev/null || true
}

ensure_tools() {
  local ctx="$1" pod="$2"
  kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc \
    'apk add --no-cache tcpdump iproute2 iputils nmap bind-tools >/dev/null 2>&1 || true'
}

start_capture() {
  local ctx="$1" pod="$2" tag="$3"
  local pcap_name="${pod}-${ctx}.pcap"
  echo "[i] ${ctx}/${pod}: starting tcpdump (${DURATION}s) → /tmp/${pcap_name}"
  kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc \
    "tcpdump -i eth0 -s 0 -nn -U -w /tmp/${pcap_name} 2>/tmp/tcpdump_${pcap_name}.err & \
     TPID=\$!; sleep ${DURATION}; kill \$TPID 2>/dev/null || true; wait \$TPID 2>/dev/null || true" &
}

copy_pcaps() {
  local ctx="$1" pod="$2"
  local pcap_name="${pod}-${ctx}.pcap"
  if kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc "test -f /tmp/${pcap_name}" 2>/dev/null; then
    kubectl --context "$ctx" -n "$NS" cp "${NS}/${pod}:/tmp/${pcap_name}" "${OUTDIR}/${pcap_name}" 2>/dev/null || true
    kubectl --context "$ctx" -n "$NS" cp "${NS}/${pod}:/tmp/tcpdump_${pcap_name}.err" "${OUTDIR}/tcpdump_${pcap_name}.err" 2>/dev/null || true
    echo "  → saved ${OUTDIR}/${pcap_name}"
    # cleanup
    kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc "rm -f /tmp/${pcap_name} /tmp/tcpdump_${pcap_name}.err" >/dev/null 2>&1 || true
  else
    echo "  ! ${ctx}/${pod}: no pcap produced"
  fi
}

# --- Sanity -------------------------------------------------------------------
for ctx in "$CTX1" "$CTX2"; do
  kubectl --context "$ctx" -n "$NS" get pods >/dev/null
  for pod in "${PODS[@]}"; do
    kubectl --context "$ctx" -n "$NS" get pod "$pod" >/dev/null
  done
done

# Determine remote target Global IP (toolbox-0@CTX2)
#TARGET_GIP_POD0_CTX2="${TARGET_GIP_POD0_CTX2:-$(get_gip "$CTX2" "toolbox-0")}"
TARGET_GIP_POD0_CTX2=242.0.255.252
if [[ -z "${TARGET_GIP_POD0_CTX2}" ]]; then
  echo "[!] Could not resolve GlobalIngressIP for toolbox-0 in ${CTX2}. Set TARGET_GIP_POD0_CTX2=242.x.x.x and retry." >&2
  exit 1
fi

echo "[i] Will ping from ${CTX1}/toolbox-0 → ${CTX2}/toolbox-0 at ${TARGET_GIP_POD0_CTX2}"

echo "[i] Ensuring tools in all pods…"
for ctx in "$CTX1" "$CTX2"; do
  for pod in "${PODS[@]}"; do
    ensure_tools "$ctx" "$pod"
  done
done

# --- Kick off captures on all 4 pods -----------------------------------------
for ctx in "$CTX1" "$CTX2"; do
  for pod in "${PODS[@]}"; do
    start_capture "$ctx" "$pod" "run1"
  done
done

# --- Timed actions from toolbox-0@CTX1 ---------------------------------------
sleep "$PING_START"
PING_LOG="${OUTDIR}/ping_toolbox-0-${CTX1}.log"
echo "[i] (${CTX1}/toolbox-0) pinging ${TARGET_GIP_POD0_CTX2} for ${PING_DURATION}s…"
kubectl --context "$CTX1" -n "$NS" exec toolbox-0 -- sh -lc \
  "ping -i 0.2 -w ${PING_DURATION} ${TARGET_GIP_POD0_CTX2}" | tee "$PING_LOG" || true

declare -i now=$PING_START
if (( NMAP_START > now )); then sleep $((NMAP_START-now)); fi
NMAP_LOG="${OUTDIR}/nmap_toolbox-0-${CTX1}.log"
kubectl --context "$CTX1" -n "$NS" exec toolbox-0 -- sh -lc \
  "timeout ${NMAP_TIMEOUT}s nmap ${NMAP_FLAGS} ${NMAP_TARGET}" | tee "$NMAP_LOG" || true
# (Or use two execs with `tee -a "$NMAP_LOG"` to append.)

# --- Wait for all tcpdump sessions to finish ---------------------------------
wait || true

echo "[i] Captures complete. Copying pcaps…"
for ctx in "$CTX1" "$CTX2"; do
  for pod in "${PODS[@]}"; do
    copy_pcaps "$ctx" "$pod"
  done
done

echo

command -v tshark >/dev/null 2>&1 || { echo "[!] tshark not found on host. Install Wireshark/tshark."; exit 1; }

# Optional display filter (e.g., DISPLAY_FILTER='icmp || tcp.port==8080')
DISPLAY_FILTER="${DISPLAY_FILTER:-}"

# Build optional filter args
TSHARK_FILTER_ARGS=()
if [[ -n "$DISPLAY_FILTER" ]]; then
  TSHARK_FILTER_ARGS=(-Y "$DISPLAY_FILTER")
fi

# --- Aggregate per-second counts into a long (tidy) CSV ---
# --- Aggregate per-second counts into a long (tidy) CSV ---
COUNTS_CSV="$OUTDIR/packet_counts.csv"
echo "pod,second,t_remaining,count" > "$COUNTS_CSV"

# Read experiment start (fallback to 0 if missing)
if [[ -f "${OUTDIR}/t0_epoch.txt" ]]; then
  EXPERIMENT_T0="$(cat "${OUTDIR}/t0_epoch.txt")"
else
  EXPERIMENT_T0=0
fi

for pcap in "$OUTDIR"/*.pcap; do
  [[ -e "$pcap" ]] || continue
  pod="$(basename "$pcap" .pcap)"

  if [[ ! -s "$pcap" ]]; then
    awk -v pod="$pod" -v dur="$DURATION" 'BEGIN{for(i=0;i<dur;i++) printf "%s,%d,%d,%d\n",pod,i,dur-1-i,0}' >> "$COUNTS_CSV"
    continue
  fi

  # Bin by absolute time since experiment T0
  LC_ALL=C tshark -r "$pcap" -T fields -e frame.time_epoch "${TSHARK_FILTER_ARGS[@]}" 2>/dev/null \
  | awk -v dur="$DURATION" -v pod="$pod" -v t0="$EXPERIMENT_T0" '
      {
        s = int($1 - t0);              # seconds since experiment start
        if (s >= 0 && s < dur) c[s]++;
      }
      END {
        for (i=0; i<dur; i++) {
          tr = dur - 1 - i;
          printf "%s,%d,%d,%d\n", pod, i, tr, (c[i] ? c[i] : 0)
        }
      }' >> "$COUNTS_CSV"
done


echo "[✓] Done. Artifacts in: ${OUTDIR}"
ls -lh "${OUTDIR}" || true