# --- constants (adjust only if needed) ---
BASE="http://10.4.16.163:32058/onos/vnets/api"

AUTH="karaf:karaf"

NET_ID="setup-time"
EP1="of:f04c130363d61c18/3"
EP2="of:c19501e58a578288/3"

# --- JSON payloads (robustly built with jq) ---
NET_JSON_CREATE=$(jq -n --arg id "$NET_ID" '{networkId: $id}')
NET_JSON_PORT=$(jq -n --arg id "$NET_ID" --arg ep1 "$EP1" --arg ep2 "$EP2" \
  '{networkId: $id, networkEndpoints: [$ep1, $ep2]}')

# sanity: see what you’re sending
echo "$NET_JSON_CREATE"
echo "$NET_JSON_PORT"

# --- equivalent curl sequence to your Go example ---

# 1) DELETE /networks/<id>
# curl -sS -u "$AUTH" -X DELETE "$BASE/networks/$NET_ID"

# 2) POST /networks          (create the network)
curl -sS -u "$AUTH" -H 'Content-Type: application/json' \
  -X POST -d "$NET_JSON_CREATE" "$BASE"

# 3) POST /networks/port     (attach endpoints)
curl -sS -u "$AUTH" -H 'Content-Type: application/json' \
  -X POST -d "$NET_JSON_PORT" "$BASE/port"
