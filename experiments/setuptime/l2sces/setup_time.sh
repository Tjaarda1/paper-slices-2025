#!/usr/bin/env bash
# Simple orchestrator:
# 1) DELETE network from laptop
# 2) Ensure fast ping in ping-st
# 3) In pong-st: arm tcpdump -> sleep 0.5s -> timestamp -> POST create -> capture first packet
# 4) Append a CSV row per run (computed on pod clock)

# set -euo pipefail

# Bring in your variables (kubeconfigs, pods, ONOS urls, IPs, P_MS, RUNS, OUT_DIR/CSV)
source ./experiments/setuptime/l2sces/variables.sh

cleanup() {
  kubectl --kubeconfig "$KCFG_A" -n "$NS" exec "$POD_PING" -- sh -lc '
    if [ -f /tmp/pinger.pid ]; then kill "$(cat /tmp/pinger.pid)" 2>/dev/null || true; rm -f /tmp/pinger.pid; fi
    pkill -f "ping -i .* -I '"$NET_IF"' '"$PONG_IP"'" 2>/dev/null || true
  ' || true
}

# --- deps ---
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need kubectl; need curl; need awk; need base64
mkdir -p "$OUT_DIR"

# CSV header
if [[ ! -f "$OUT_CSV" ]]; then
  echo "run,apply_epoch_ns,first_icmp_epoch_ns_pong,approx_offset_ns,first_icmp_epoch_ns_laptop,probe_period_ms,estimate_ms,error_bound_ms,src_ping_ip,dst_pong_ip" > "$OUT_CSV"
fi

echo "[*] Fetching network JSON once (must exist now)…"
NET_JSON="$(curl -sS -u "$ONOS_AUTH" -H 'Accept: application/json' "$ONOS_NET_URL")"
if [[ -z "$NET_JSON" || "$NET_JSON" == "null" ]]; then
  echo "ERROR: GET $ONOS_NET_URL returned empty. Make sure the network exists before starting." >&2
  exit 1
fi
NET_JSON_B64="$(printf '%s' "$NET_JSON" | base64 | tr -d '\n')"

echo "[*] Ensuring pods are Ready…"
kubectl --kubeconfig "$KCFG_A" -n "$NS" wait --for=condition=Ready pod/"$POD_PING" --timeout=120s >/dev/null
kubectl --kubeconfig "$KCFG_B" -n "$NS" wait --for=condition=Ready pod/"$POD_PONG" --timeout=120s >/dev/null

echo "[*] Ensuring fast ping loop in ${POD_PING} → ${PONG_IP} via ${NET_IF} (i=${P_MS}ms)…"
kubectl --kubeconfig "$KCFG_A" -n "$NS" exec "$POD_PING" -- sh -lc '
  INTERVAL=$(awk '"'"'BEGIN{printf "%.3f",'$P_MS'/1000}'"'"')
  nohup ping -i "$INTERVAL" -s 8 -W 1 -I "'"$NET_IF"'" "'"$PONG_IP"'" >/tmp/pinger.log 2>&1 &
  echo $! > /tmp/pinger.pid
'
>/dev/null

P_HALF_MS="$(awk -v p="$P_MS" 'BEGIN{printf "%.3f", p/2.0}')"
echo "[*] Running ${RUNS} iterations (error bound ±${P_HALF_MS} ms)…"

for i in $(seq 1 "$RUNS"); do
  echo
  echo "[run $i/$RUNS] DELETE → (pod) tcpdump+sleep→timestamp→POST create→capture"

  # 1) DELETE network from laptop
  curl -sS -u "$ONOS_AUTH" -X DELETE "$ONOS_NET_URL" >/dev/null || true

  # 2) Do the measuring phase inside the pong pod
  ROW="$(
    kubectl --kubeconfig "$KCFG_B" -n "$NS" exec "$POD_PONG" -- \
      env \
        NET_IF="$NET_IF" \
        PING_IP="$PING_IP" \
        PONG_IP="$PONG_IP" \
        P_MS="$P_MS" \
        P_HALF_MS="$P_HALF_MS" \
        ONOS_POST_URL="$ONOS_POST_URL" \
        ONOS_AUTH="$ONOS_AUTH" \
        NET_ID="setup-time" \
      sh -s <<'POD'

# Ensure required tools are present (Alpine base)
apk add --no-cache tcpdump curl coreutils >/dev/null 2>&1 || true

# 1) Arm tcpdump FIRST
SNIFF_FILE="$(mktemp)"
( tcpdump -n -i "$NET_IF" -tt icmp and src host "$PING_IP" -c 1 2>/dev/null \
    | awk '{printf("%0.0f\n",$1*1e9)}' > "$SNIFF_FILE" ) &
SNIFF_PID=$!

# 2) Give tcpdump 0.5s to be fully armed (this is BEFORE we take APPLY_NS)
sleep 0.5
EP1="of:f04c130363d61c18/3"
EP2="of:c19501e58a578288/3"

# --- JSON payloads (robustly built with jq) ---
NET_JSON_CREATE=$(jq -n --arg id "$NET_ID" '{networkId: $id}')
NET_JSON_PORT=$(jq -n --arg id "$NET_ID" --arg ep1 "$EP1" --arg ep2 "$EP2" \
  '{networkId: $id, networkEndpoints: [$ep1, $ep2]}')

# 3) Timestamp (pod clock) and CREATE (POST) to your collection endpoint
APPLY_NS="$(date +%s%N)"

curl -sS -u "$ONOS_AUTH" -H 'Content-Type: application/json'  -X POST -d "$NET_JSON_CREATE" "$ONOS_POST_URL"

curl -sS -u "$ONOS_AUTH" -H 'Content-Type: application/json'   -X POST -d "$NET_JSON_PORT" "$ONOS_POST_URL/port"


# 4) Wait for first ICMP arrival
wait "$SNIFF_PID" || true
if [ ! -s "$SNIFF_FILE" ]; then
  echo "ERROR,noicmp"
  exit 0
fi

FIRST_NS="$(cat "$SNIFF_FILE")"
rm -f "$SNIFF_FILE" /tmp/net.json || true

# 5) Compute estimate on pod (single clock). Sleep is already excluded since APPLY_NS is after sleep.
EST_MS="$(awk -v first="$FIRST_NS" -v apply="$APPLY_NS" -v p="$P_MS" \
            'BEGIN{printf "%.3f", ((first-apply)/1e6) - (p/2.0)}')"

# 6) Emit the CSV tail (offset=0; laptop==pod clock by design)
echo "$APPLY_NS,$FIRST_NS,0,$FIRST_NS,$P_MS,$EST_MS,$P_HALF_MS,$PING_IP,$PONG_IP"
POD
  )"

  if [[ "$ROW" == "ERROR,noicmp" || -z "$ROW" ]]; then
    echo "  (no ICMP captured; skipping row)"
    continue
  fi

  echo "${i},${ROW}" >> "$OUT_CSV"
  echo "  -> appended: ${ROW}"
  sleep 1
done

cleanup
echo
echo "[*] Done. CSV at: $OUT_CSV"


 trap cleanup SIGINT