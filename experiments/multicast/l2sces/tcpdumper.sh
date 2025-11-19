#!/usr/bin/env bash
# multicluster_tcpdump_ping_nmap.sh
# Start tcpdump on 4 pods (2 in each cluster), then:
#  - toolbox-0@sub-managed-1 pings toolbox-0@sub-managed-2 (by Global IP)
#  - toolbox-0@sub-managed-1 runs an nmap scan against 242.0.0.0/8 (configurable)
# Captures are copied locally as: toolbox-<idx>-<context>.pcap

set -euo pipefail

# --- Config (override via env) -------------------------------------------------
KUBECONFIG_PATH="${KUBECONFIG_PATH:-local/configs/kubeconfig}"
CTX1="${CTX1:-l2sces-managed-1}"
CTX2="${CTX2:-l2sces-managed-2}"
NS="${NS:-l2sces-system}"

# Capture timing
DURATION="${DURATION:-60}"          # total tcpdump capture time (seconds)
PING_START="${PING_START:-5}"       # when to start ping (s after capture start)
PING_DURATION="${PING_DURATION:-10}" # ping duration in seconds
MULTICAST_START="${MULTICAST_START:-20}"      # when to start nmap (s after capture start)
NMAP_TIMEOUT="${NMAP_TIMEOUT:-60}"  # hard time limit for nmap (seconds)
TARGET_IP_POD0_CTX2="10.1.128.3"
# Nmap target (warning: /8 is huge; default is what you asked for)
NMAP_TARGET="${NMAP_TARGET:-10.8.64.0/24}"
# Use a fast, ICMP-only host discovery to keep runtime reasonable
NMAP_FLAGS="${NMAP_FLAGS:--sn -PE -e net1 -T4 --max-retries 1 --max-rtt-timeout 500ms --initial-rtt-timeout 250ms}"


# Output directory
OUTDIR="${OUTDIR:-./experiments/multicast/captures/$(date +%Y%m%d_%H%M%S)}"
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
    'apk add --no-cache iproute2 >/dev/null 2>&1 || true; ip neigh flush dev net1 || true' || true
}

flush_arp "$CTX1" ping 
flush_arp "$CTX2" pong 
flush_arp "$CTX2" pung 


ensure_tools() {
  local ctx="$1" pod="$2"
  kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc \
    'apk add --no-cache tcpdump iproute2 iputils bind-tools iperf >/dev/null 2>&1 || true'
}

start_capture() {
  local ctx="$1" pod="$2" tag="$3"
  local pcap_name="${pod}-${ctx}.pcap"
  echo "[i] ${ctx}/${pod}: starting tcpdump (${DURATION}s) → /tmp/${pcap_name}"
  kubectl --context "$ctx" -n "$NS" exec "$pod" -- sh -lc \
    "tcpdump -i net1 -s 0 -nn -U  -w /tmp/${pcap_name} 2>/tmp/tcpdump_${pcap_name}.err & \
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


echo "[i] Will ping from ${CTX1}/ping → ${CTX2}/pong"

echo "[i] Ensuring tools in all pods…"

ensure_tools "$CTX1" ping 
ensure_tools "$CTX2" pong 
ensure_tools "$CTX2" pung 

# --- Kick off captures on all 4 pods -----------------------------------------

start_capture "$CTX1" ping  "run1"
start_capture "$CTX2" pong  "run1"
start_capture "$CTX2" pung  "run1"


# --- Timed actions from toolbox-0@CTX1 ---------------------------------------
sleep "$PING_START"
PING_LOG="${OUTDIR}/ping_${CTX1}.log"
echo "[i] (${CTX1}/ping) broadcast ${TARGET_IP_POD0_CTX2} for ${PING_DURATION}s…"
kubectl --context "$CTX1" -n "$NS" exec ping -- sh -lc \
  "ping -b -I net1  -i 0.2 -w ${PING_DURATION} 10.1.255.255" | tee "$PING_LOG" || true

# --- Multicast test (servers first, then client) ------------------------------
MULTICAST_GROUP="${MULTICAST_GROUP:-239.94.1.1}"
SRC_IF="net1"

# discover client source IP on net1 (CTX1/ping)
CLIENT_SRC_IP="$(
  kubectl --context "$CTX1" -n "$NS" exec ping -- sh -lc \
    "ip -4 -o addr show dev $SRC_IF | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null | tail -n1
)"

if [[ -z "$CLIENT_SRC_IP" ]]; then
  echo "[!] Could not determine client IP on $SRC_IF in ${CTX1}/ping"
  exit 1
fi
sleep 5
MULTICAST_CLIENT_LOG="${OUTDIR}/multicast_client_${CTX1}.log"
MULTICAST_PONG_LOG="${OUTDIR}/multicast_srv_pong_${CTX2}.log"
MULTICAST_PUNG_LOG="${OUTDIR}/multicast_srv_pung_${CTX2}.log"

echo "[i] (${CTX2}/pong) starting multicast UDP server on ${MULTICAST_GROUP}…"
# Run server in background; log locally; don't let failures kill the script
(kubectl --context "$CTX2" -n "$NS" exec pong -- sh -lc \
  "iperf -s -u -B ${MULTICAST_GROUP} -i 1" \
  >"${MULTICAST_PONG_LOG}" 2>&1 || true) &

echo "[i] (${CTX2}/pung) starting multicast UDP server on ${MULTICAST_GROUP}…"
(kubectl --context "$CTX2" -n "$NS" exec pung -- sh -lc \
  "iperf -s -u -B ${MULTICAST_GROUP} -i 1" \
  >"${MULTICAST_PUNG_LOG}" 2>&1 || true) &

sleep 2

echo "[i] (${CTX1}/ping) sending multicast to ${MULTICAST_GROUP} from ${CLIENT_SRC_IP} for ${PING_DURATION}s…"
# Client runs in foreground so it aligns with capture window
kubectl --context "$CTX1" -n "$NS" exec ping -- sh -lc \
  "iperf -c ${MULTICAST_GROUP} -u -B ${CLIENT_SRC_IP} -T 32 -t ${PING_DURATION} -i 1 -b 200k -l 1200" \
  | tee -a "${MULTICAST_CLIENT_LOG}" || true

# give servers a moment to flush output
sleep 2



echo "[i] Captures complete. Copying pcaps…"


copy_pcaps "$CTX1" ping  
copy_pcaps "$CTX2" pong  
copy_pcaps "$CTX2" pung  

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