now redo this script for this scenario. We will have toolbox-0-sub-managed-1.pcap for instance. And the script is going like this: first tcpdump on every pod, and ill show you the ip addresses now, which toolbox-0-sub-managed-1 will ping toolbox-0-sub-managed-2, you will perform an nmap of the 242.0.0.0/8 from toolbox-0-sub-managed-1 alex@alex:~/Documents/papers/paperslices2025/paper-slices-2025$ kubectl -n net-test get globalingressip --context sub-managed-1 --kubeconfig local/configs/kubeconfig NAME IP pod-toolbox-0 242.1.255.251 pod-toolbox-1 242.1.255.250 alex@alex:~/Documents/papers/paperslices2025/paper-slices-2025$ kubectl -n net-test get globalingressip --context sub-managed-2 --kubeconfig local/configs/kubeconfig NAME IP pod-toolbox-0 242.0.255.252 pod-toolbox-1 242.0.255.251: #!/usr/bin/env bash
# experiments/pods_tcpdump/tcpdumper.sh
# One round: 20s tcpdump on pinger/sniffer/sleepy; at t=5s start 10s ping pinger->sniffer.
# Flushes ARP caches by default; copies pcaps under this folder; runs podstcpdump.r on them.

set -euo pipefail

# --- Paths (resolve to this script's directory) ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
R_SCRIPT="${R_SCRIPT:-$SCRIPT_DIR/podstcpdump.r}"

# --- Config ---
NS="${NS:-net-lab}"
PINGER="${PINGER:-pinger}"
SNIFFER="${SNIFFER:-sniffer}"
SLEEPY="${SLEEPY:-sleepy}"

DURATION="${DURATION:-40}"           # total capture window
START_OFFSET="${START_OFFSET:-5}"    # when ping starts (sec after capture start)
PING_DURATION="${PING_DURATION:-10}" # ping length (sec)

# Flush ARP caches by default so ARP appears at capture start
FLUSH_ARP="${FLUSH_ARP:-1}"

# Optional Wireshark display filter for the R analysis (leave empty for all traffic)
DISPLAY_FILTER="${DISPLAY_FILTER:-}"

# Output dir: lives UNDER experiments/pods_tcpdump by default
OUTDIR="${OUTDIR:-$SCRIPT_DIR/captures/$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUTDIR"

PODS=("$PINGER" "$SNIFFER" "$SLEEPY")
CAPTURE_PIDS=()

# Sanity check
if (( START_OFFSET + PING_DURATION > DURATION )); then
  echo "[!] START_OFFSET + PING_DURATION exceeds DURATION"; exit 1
fi

echo "[i] Namespace: $NS"
echo "[i] Pods: ${PODS[*]}"
kubectl get pods -n "$NS" >/dev/null

# Sniffer IP
SNIP="$(kubectl get pod "$SNIFFER" -n "$NS" -o jsonpath='{.status.podIP}')"
echo "[i] Sniffer IP: $SNIP"

# Ensure tools
echo "[i] Ensuring tcpdump in all pods and ping in pinger…"
for P in "${PODS[@]}"; do
  kubectl exec -n "$NS" "$P" -- sh -lc 'command -v tcpdump >/dev/null 2>&1 || apk add --no-cache tcpdump >/dev/null' || true
done
kubectl exec -n "$NS" "$PINGER" -- sh -lc 'command -v ping >/dev/null 2>&1 || apk add --no-cache iputils >/dev/null' || true
kubectl exec -n "$NS" "$PINGER" -- sh -lc 'command -v nmap >/dev/null 2>&1 || apk add --no-cache nmap >/dev/null' || true

# Flush ARP caches (ip neigh) if enabled
if [[ "$FLUSH_ARP" == "1" ]]; then
  echo "[i] Flushing ARP in all pods…"
  for P in "${PODS[@]}"; do
    kubectl exec -n "$NS" "$P" -- sh -lc 'apk add --no-cache iproute2 >/dev/null 2>&1 || true; ip neigh flush dev eth0 || true' || true
  done
fi

# Start a 20s capture in one pod (track child PID properly)
start_capture() {
  local pod="$1" tag="$2"
  kubectl exec -n "$NS" "$pod" -- sh -lc \
    "tcpdump -i eth0 -s 0 -nn -U -w /tmp/${pod}_${tag}.pcap 2>/tmp/tcpdump_${pod}_${tag}.err & \
     PID=\$!; sleep $DURATION; kill \$PID 2>/dev/null || true; wait \$PID 2>/dev/null || true" &
  CAPTURE_PIDS+=("$!")
}

echo "[i] Starting ${DURATION}s tcpdump on: ${PODS[*]}"
for P in "${PODS[@]}"; do start_capture "$P" "1"; done

# At t = START_OFFSET, run ping for PING_DURATION
sleep "$START_OFFSET"
echo "[i] Starting ${PING_DURATION}s ping at t=${START_OFFSET}s: $PINGER → $SNIP"
kubectl exec -n "$NS" "$PINGER" -- sh -lc "ping -i 0.1 -w $PING_DURATION $SNIP" > "$OUTDIR/ping.log" 2>&1 || true

sleep "$START_OFFSET"
echo "[i] Starting ${PING_DURATION}s nmap at t=${START_OFFSET}s: scanning"
kubectl exec -n "$NS" "$PINGER" -- sh -lc "nmap 10.233.64.0/24" > "$OUTDIR/ping.log" 2>&1 || true

# Wait for captures to finish
for pid in "${CAPTURE_PIDS[@]}"; do wait "$pid" || true; done
echo "[i] Capture complete. Copying pcaps…"

# Copy pcaps + tcpdump stderr; clean up in pods
for P in "${PODS[@]}"; do
  kubectl cp -n "$NS" "$P:/tmp/${P}_1.pcap" "$OUTDIR/${P}_1.pcap" 2>/dev/null && \
    echo "  → saved $OUTDIR/${P}_1.pcap" || echo "  ! could not copy pcap from $P"
  kubectl cp -n "$NS" "$P:/tmp/tcpdump_${P}_1.err" "$OUTDIR/${P}_tcpdump.err" 2>/dev/null || true
  kubectl exec -n "$NS" "$P" -- sh -lc "rm -f /tmp/${P}_1.pcap /tmp/tcpdump_${P}_1.err" >/dev/null 2>&1 || true
done


command -v tshark >/dev/null 2>&1 || { echo "[!] tshark not found on host. Install Wireshark/tshark."; exit 1; }

# --- Build optional display filter args for tshark (reuse your DISPLAY_FILTER var) ---
TSHARK_FILTER_ARGS=()
if [[ -n "${DISPLAY_FILTER:-}" ]]; then
  TSHARK_FILTER_ARGS=(-Y "$DISPLAY_FILTER")
fi

# --- Aggregate per-second counts into a long (tidy) CSV ---
COUNTS_CSV="$OUTDIR/packet_counts.csv"
echo "pod,second,t_remaining,count" > "$COUNTS_CSV"

for pcap in "$OUTDIR"/*_1.pcap; do
  [[ -e "$pcap" ]] || continue
  pod="$(basename "$pcap" | sed -E 's/_1\.pcap$//')"

  if [[ ! -s "$pcap" ]]; then
    # pcap missing/empty: output zeros for all seconds so plots line up
    awk -v pod="$pod" -v dur="$DURATION" 'BEGIN{for(i=0;i<dur;i++) printf "%s,%d,%d,%d\n",pod,i,dur-1-i,0}' >> "$COUNTS_CSV"
    continue
  fi

  # Extract relative times, floor to second, count within [0, DURATION-1]
  tshark -r "$pcap" -T fields -e frame.time_relative "${TSHARK_FILTER_ARGS[@]}" 2>/dev/null \
  | awk -v dur="$DURATION" -v pod="$pod" '
      { s = int($1); if (s >= 0 && s < dur) c[s]++ }
      END {
        for (i=0; i<dur; i++) {
          tr = dur - 1 - i;                  # countdown column, if you prefer plotting that
          printf "%s,%d,%d,%d\n", pod, i, tr, (c[i] ? c[i] : 0)
        }
      }' >> "$COUNTS_CSV"
done

echo "[✓] Wrote $COUNTS_CSV"

echo "[✓] Done. Files in: $OUTDIR"
ls -lh "$OUTDIR"