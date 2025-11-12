#!/usr/bin/env bash
# Merge per-cluster kubeconfigs into a single kubeconfig with unique names.
# Input dir:  ./local/configs/k8s/
# Output file: ./local/configs/kubeconfig
# Tools used: bash, kubectl, base64, mktemp, coreutils

set -euo pipefail
shopt -s nullglob

INDIR="local/configs/k8s"
OUT="local/configs/kubeconfig"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT" "$OUT.tmp"
touch "$OUT"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required on PATH." >&2
  exit 1
fi

# Helper to fetch a jsonpath from a kubeconfig file (allow missing keys).
jp() {
  # $1=file, $2=jsonpath
  kubectl --kubeconfig "$1" config view --raw -o "jsonpath=${2}" 2>/dev/null || true
}

first_context=""

echo "Merging kubeconfigs from '$INDIR' into '$OUT'..."
files=( "$INDIR"/kubeconfig-*.yaml "$INDIR"/kubeconfig-*.yml )
if [ ${#files[@]} -eq 0 ]; then
  echo "No kubeconfig-*.yaml files found in $INDIR" >&2
  exit 1
fi

for f in "${files[@]}"; do
  base="$(basename "$f")"
  stem="${base%.*}"               # e.g., kubeconfig-l2sces-control
  name="${stem#kubeconfig-}"      # e.g., l2sces-control

  cluster="$name"
  user="$name"
  context="$name"

  echo "• Importing $base  →  cluster='$cluster', user='$user', context='$context'"

  # --- Extract cluster bits ---
  server="$(jp "$f" '{.clusters[0].cluster.server}')"
  if [ -z "$server" ]; then
    echo "  Skipping (no cluster.server in $base)" >&2
    continue
  fi
  tls_name="$(jp "$f" '{.clusters[0].cluster.tls-server-name}')"
  ca_data="$(jp "$f" '{.clusters[0].cluster.certificate-authority-data}')"
  ca_file="$(jp "$f" '{.clusters[0].cluster.certificate-authority}')"
  insecure="$(jp "$f" '{.clusters[0].cluster.insecure-skip-tls-verify}')"

  cluster_args=( "--server=$server" )
  [ -n "$tls_name" ] && cluster_args+=( "--tls-server-name=$tls_name" )

  tmp_ca=""
  if [ "$insecure" = "true" ]; then
    cluster_args+=( "--insecure-skip-tls-verify=true" )
  else
    if [ -n "$ca_data" ]; then
      tmp_ca="$(mktemp)"
      printf '%s' "$ca_data" | base64 -d > "$tmp_ca"
      cluster_args+=( "--certificate-authority=$tmp_ca" "--embed-certs=true" )
    elif [ -n "$ca_file" ]; then
      cluster_args+=( "--certificate-authority=$ca_file" "--embed-certs=true" )
    fi
  fi

  kubectl --kubeconfig "$OUT" config set-cluster "$cluster" "${cluster_args[@]}" >/dev/null

  # --- Extract user bits ---
  token="$(jp "$f" '{.users[0].user.token}')"
  username="$(jp "$f" '{.users[0].user.username}')"
  password="$(jp "$f" '{.users[0].user.password}')"

  cc_data="$(jp "$f" '{.users[0].user.client-certificate-data}')"
  cc_file="$(jp "$f" '{.users[0].user.client-certificate}')"
  ck_data="$(jp "$f" '{.users[0].user.client-key-data}')"
  ck_file="$(jp "$f" '{.users[0].user.client-key}')"

  exec_cmd="$(jp "$f" '{.users[0].user.exec.command}')"
  exec_api="$(jp "$f" '{.users[0].user.exec.apiVersion}')"
  exec_args_raw="$(jp "$f" '{range .users[0].user.exec.args[*]}{.}{"\n"}{end}')"
  exec_env_names="$(jp "$f" '{range .users[0].user.exec.env[*]}{.name}{"\n"}{end}')"
  exec_env_values="$(jp "$f" '{range .users[0].user.exec.env[*]}{.value}{"\n"}{end}')"

  user_args=()
  tmp_cc=""
  tmp_ck=""

  # Token / basic auth
  [ -n "$token" ] && user_args+=( "--token=$token" )
  { [ -n "$username" ] || [ -n "$password" ]; } && {
    [ -n "$username" ] && user_args+=( "--username=$username" )
    [ -n "$password" ] && user_args+=( "--password=$password" )
  }

  # Client certs
  if [ -n "$cc_data$ck_data$cc_file$ck_file" ]; then
    if [ -n "$cc_data" ]; then
      tmp_cc="$(mktemp)"; printf '%s' "$cc_data" | base64 -d > "$tmp_cc"
      user_args+=( "--client-certificate=$tmp_cc" )
    elif [ -n "$cc_file" ]; then
      user_args+=( "--client-certificate=$cc_file" )
    fi
    if [ -n "$ck_data" ]; then
      tmp_ck="$(mktemp)"; printf '%s' "$ck_data" | base64 -d > "$tmp_ck"
      user_args+=( "--client-key=$tmp_ck" )
    elif [ -n "$ck_file" ]; then
      user_args+=( "--client-key=$ck_file" )
    fi
    user_args+=( "--embed-certs=true" )
  fi

  # Exec auth (aws, gcloud, etc.)
  if [ -n "$exec_cmd" ]; then
    user_args+=( "--exec-command=$exec_cmd" )
    [ -n "$exec_api" ] && user_args+=( "--exec-api-version=$exec_api" )
    if [ -n "$exec_args_raw" ]; then
      while IFS= read -r a; do
        [ -n "$a" ] && user_args+=( "--exec-arg=$a" )
      done <<< "$exec_args_raw"
    fi
    if [ -n "$exec_env_names" ]; then
      paste -d'=' <(printf '%s\n' "$exec_env_names") <(printf '%s\n' "$exec_env_values") | \
      while IFS= read -r kv; do
        [ -n "$kv" ] && user_args+=( "--exec-env=$kv" )
      done
    fi
  fi

  kubectl --kubeconfig "$OUT" config set-credentials "$user" "${user_args[@]}" >/dev/null

  # --- Context (preserve namespace if present) ---
  namespace="$(jp "$f" '{.contexts[0].context.namespace}')"
  ctx_args=( "--cluster=$cluster" "--user=$user" )
  [ -n "$namespace" ] && ctx_args+=( "--namespace=$namespace" )
  kubectl --kubeconfig "$OUT" config set-context "$context" "${ctx_args[@]}" >/dev/null

  # Clean up temps
  [ -n "${tmp_ca:-}" ] && rm -f "$tmp_ca"
  [ -n "${tmp_cc:-}" ] && rm -f "$tmp_cc"
  [ -n "${tmp_ck:-}" ] && rm -f "$tmp_ck"

  [ -z "$first_context" ] && first_context="$context"
done

# Flatten to remove any possible anchors/duplicates and ensure raw data is embedded.
KUBECONFIG="$OUT" kubectl config view --raw --flatten > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

# Set a default current-context (first one imported).
if [ -n "$first_context" ]; then
  kubectl --kubeconfig "$OUT" config use-context "$first_context" >/dev/null
fi

echo "✓ Wrote merged kubeconfig to $OUT"
