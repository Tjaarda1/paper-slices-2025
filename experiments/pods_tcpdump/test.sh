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
DURATION="${DURATION:-150}"          # total tcpdump capture time (seconds)
PING_START="${PING_START:-5}"       # when to start ping (s after capture start)
PING_DURATION="${PING_DURATION:-10}" # ping duration in seconds
NMAP_START="${NMAP_START:-20}"      # when to start nmap (s after capture start)
NMAP_TIMEOUT="${NMAP_TIMEOUT:-150}"  # hard time limit for nmap (seconds)

# Nmap target (warning: /8 is huge; default is what you asked for)
NMAP_TARGET="${NMAP_TARGET:-242.0.0.0/15}"
# Use a fast, ICMP-only host discovery to keep runtime reasonable
NMAP_FLAGS="${NMAP_FLAGS:--sn -PE -T4 --max-retries 1 --max-rtt-timeout 500ms --initial-rtt-timeout 250ms}"

# Pods to capture on (must exist in each cluster)
PODS=("toolbox-0" "toolbox-1")

# Output directory
OUTDIR="${OUTDIR:-./experiments/pods_tcpdump/captures/20250825_150013}"

command -v tshark >/dev/null 2>&1 || { echo "[!] tshark not found on host. Install Wireshark/tshark."; exit 1; }

# Optional display filter (e.g., DISPLAY_FILTER='icmp || tcp.port==8080')
DISPLAY_FILTER="${DISPLAY_FILTER:-}"

# Build optional filter args
TSHARK_FILTER_ARGS=()
if [[ -n "$DISPLAY_FILTER" ]]; then
  TSHARK_FILTER_ARGS=(-Y "$DISPLAY_FILTER")
fi

# --- Aggregate per-second counts into a long (tidy) CSV ---
COUNTS_CSV="$OUTDIR/packet_counts.csv"
echo "pod,second,t_remaining,count" > "$COUNTS_CSV"

# Match the actual filenames we created earlier: *.pcap
for pcap in "$OUTDIR"/*.pcap; do
  [[ -e "$pcap" ]] || continue

  # Derive the pod label from the filename (strip only the .pcap suffix)
  pod="$(basename "$pcap" .pcap)"

  if [[ ! -s "$pcap" ]]; then
    # pcap missing/empty: output zeros so plots line up
    awk -v pod="$pod" -v dur="$DURATION" 'BEGIN{for(i=0;i<dur;i++) printf "%s,%d,%d,%d\n",pod,i,dur-1-i,0}' >> "$COUNTS_CSV"
    continue
  fi

  # Use C locale so decimal separator is a dot for frame.time_relative
  LC_ALL=C tshark -r "$pcap" -T fields -e frame.time_relative "${TSHARK_FILTER_ARGS[@]}" 2>/dev/null \
  | awk -v dur="$DURATION" -v pod="$pod" '
      { s = int($1); if (s >= 0 && s < dur) c[s]++ }
      END {
        for (i=0; i<dur; i++) {
          tr = dur - 1 - i;
          printf "%s,%d,%d,%d\n", pod, i, tr, (c[i] ? c[i] : 0)
        }
      }' >> "$COUNTS_CSV"
done

echo "[✓] Done. Artifacts in: ${OUTDIR}"
ls -lh "${OUTDIR}" || true
