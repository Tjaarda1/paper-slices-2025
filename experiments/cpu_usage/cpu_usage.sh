#!/usr/bin/env bash
set -euo pipefail


OUT_CSV="experiments/cpu_usage/captures/k8s_usage_12h.csv"

# Time settings
END_TS=$(date -u +%s)
START_TS=$((END_TS - 12*60*60))       # last 12 hours

# Sampling plan
WIN="1m"
TIMEFRAME_H=24
N_POINTS_1=1000
N_POINTS_2=500

STEP_1=$(( TIMEFRAME_H * 3600 / N_POINTS_1 ))
STEP_2=$(( TIMEFRAME_H * 3600 / N_POINTS_2 ))   

echo $STEP_1
# Apps, clusters, and namespaces
declare -A NS
NS[l2sces]="l2sces-system"
NS[submariner]="submariner-operator"

L2SM_CONTROL="l2sces-control"
L2SM_MANAGED=( "l2sces-managed-1" "l2sces-managed-2" )

SUB_CONTROL="sub-control"
SUB_MANAGED=( "sub-managed-1" "sub-managed-2" )

# CSV header
echo "timestamp,iso8601,app,plane,cluster,cpu_cores,memory_bytes" > "$OUT_CSV"

# --- Helper: query_range wrapper ------------------------------------------------
# Args: query start end step_seconds -> prints raw JSON
query_range() {
  local q="$1" start="$2" end="$3" step_s="$4"
  curl -sS -G "$PROM/api/v1/query_range" \
    --data-urlencode "query=${q}" \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${end}" \
    --data-urlencode "step=${step_s}s"
}

# --- Helper: fetch CPU & MEM series and append CSV rows -------------------------
# Args: app plane cluster namespace limit_count step_seconds
fetch_and_emit() {
  local app="$1" plane="$2" cluster="$3" ns="$4" limit="$5" step_s="$6"

  # PromQL:
  # CPU cores: sum over all containers in namespace
  local CPU_Q="sum(rate(container_cpu_usage_seconds_total{cluster=\"${cluster}\",container_label_io_cri_containerd_kind=\"container\",container_label_io_kubernetes_pod_namespace=\"${ns}\"}[${WIN}]))"
  # Memory bytes (smoothed over 5m): sum of avg_over_time(working_set)
  local MEM_Q="sum(avg_over_time(container_memory_working_set_bytes{cluster=\"${cluster}\",container_label_io_cri_containerd_kind=\"container\",container_label_io_kubernetes_pod_namespace=\"${ns}\"}[${WIN}]))"

  # Query Prometheus
  local cpu_json mem_json
  cpu_json="$(query_range "$CPU_Q" "$START_TS" "$END_TS" "$step_s")"
  mem_json="$(query_range "$MEM_Q" "$START_TS" "$END_TS" "$step_s")"
  # Join CPU & MEM on index; keep the last N=$limit points; append as CSV rows
jq -nr --arg app "$app" --arg plane "$plane" --arg cluster "$cluster" --argjson limit "$limit" \
   --slurpfile CPU <(printf '%s' "$cpu_json") \
   --slurpfile MEM <(printf '%s' "$mem_json") '
    # Return .data.result[0].values or [] from the slurped files
    def vals: (.data.result | if length>0 then .[0].values else [] end);

    ($CPU[0] | vals) as $cvals |
    ($MEM[0] | vals) as $mvals |
    if ($cvals|length)==0 or ($mvals|length)==0 then empty
    else
      ([$cvals|length, $mvals|length] | min) as $n |
      (if $n > $limit then $n - $limit else 0 end) as $start |
      foreach range($start; $n) as $i (null;
        ($cvals[$i][0]|tonumber) as $ts
        | ($cvals[$i][1]|tonumber) as $cpu
        | ($mvals[$i][1]|tonumber) as $mem
        | [$ts,
           ($ts | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")),
           $app, $plane, $cluster, $cpu, $mem] | @csv
      )
    end
   ' >> "$OUT_CSV"


}

# ---------------- l2sces ----------------
# Control: $N_POINTS_1 points
fetch_and_emit "l2sces" "control" "$L2SM_CONTROL" "${NS[l2sces]}" $N_POINTS_1 "$STEP_1"
# Managed: $N_POINTS_2 points per cluster
for c in "${L2SM_MANAGED[@]}"; do
  fetch_and_emit "l2sces" "managed" "$c" "${NS[l2sces]}" $N_POINTS_2 "$STEP_2"
done

# ---------------- submariner ----------------
# Control: $N_POINTS_1 points
fetch_and_emit "submariner" "control" "$SUB_CONTROL" "${NS[submariner]}" $N_POINTS_1 "$STEP_1"
# Managed: 25 points per cluster
for c in "${SUB_MANAGED[@]}"; do
  fetch_and_emit "submariner" "managed" "$c" "${NS[submariner]}" $N_POINTS_2 "$STEP_2"
done

# Optional: sort rows by timestamp (keeps header at top)
{ head -n1 "$OUT_CSV" && tail -n +2 "$OUT_CSV" | sort -n -t, -k1,1; } > "${OUT_CSV}.tmp" && mv "${OUT_CSV}.tmp" "$OUT_CSV"

echo "Done. Wrote $(wc -l < "$OUT_CSV") lines to $OUT_CSV"
