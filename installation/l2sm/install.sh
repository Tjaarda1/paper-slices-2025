#!/usr/bin/env bash

# requisites: kubectl and go

set -euo pipefail

ROOT="$(pwd)"
LOCALCONFIG="$ROOT/local/configs"
LOCALBIN="$ROOT/local/bin"

K8S_DIR="$LOCALCONFIG/k8s"
L2SM_KEYS_DIR="$LOCALCONFIG/l2sces"

# Create dirs
mkdir -p "$LOCALBIN" "$L2SM_KEYS_DIR"

# ---- Build l2sm-md into LOCALBIN ------------------------------------------------
L2SM_MD_DIR="$LOCALBIN/l2sm-md"
L2SM_MD_BIN="$L2SM_MD_DIR/bin/apply-cert"

if [[ ! -x "$L2SM_MD_BIN" ]]; then
  echo "==> Cloning and building l2sm-md into $L2SM_MD_DIR"
  rm -rf "$L2SM_MD_DIR"
  git clone https://github.com/Networks-it-uc3m/l2sm-md.git "$L2SM_MD_DIR"
  make -C "$L2SM_MD_DIR" build
else
  echo "==> Using existing $L2SM_MD_BIN"
fi

# ---- Deploy multi-domain client on the control cluster --------------------------
echo "==> Deploying l2sm-md to control cluster"
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-control.yaml" \
  apply -f "https://github.com/Networks-it-uc3m/l2sm-md/raw/refs/heads/main/deployments/l2smmd-deployment.yaml"

# ---- Extract CA from managed clusters and register in control -------------------
echo "==> Extracting CA from managed-1"
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-1.yaml" \
  config view -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw \
  | base64 -d > "$L2SM_KEYS_DIR/cluster-managed-1.key"

echo "==> Applying cert for managed-1 into control"
"$L2SM_MD_BIN" --namespace l2sces-system \
  --kubeconfig "$K8S_DIR/kubeconfig-l2sces-control.yaml" \
  --clustername l2sces-managed-1 \
  "$L2SM_KEYS_DIR/cluster-managed-1.key"

echo "==> Extracting CA from managed-2"
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-2.yaml" \
  config view -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw \
  | base64 -d > "$L2SM_KEYS_DIR/cluster-managed-2.key"

echo "==> Applying cert for managed-2 into control"
"$L2SM_MD_BIN" --namespace l2sces-system \
  --kubeconfig "$K8S_DIR/kubeconfig-l2sces-control.yaml" \
  --clustername l2sces-managed-2 \
  "$L2SM_KEYS_DIR/cluster-managed-2.key"

# ---- Install L2S-M on the managed clusters -------------------------------------
echo "==> Installing L2S-M on managed clusters"

kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-1.yaml" \
    apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-1.yaml" \
    apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-2.yaml" \
    apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-2.yaml" \
    apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-1.yaml" wait --for=condition=Ready pods --all -A  --timeout=300s
kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-2.yaml" wait --for=condition=Ready pods --all -A  --timeout=300s


kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-1.yaml" \
  apply -f "https://github.com/Networks-it-uc3m/L2S-M/raw/refs/heads/development/deployments/l2sces-deployment.yaml"

kubectl --kubeconfig "$K8S_DIR/kubeconfig-l2sces-managed-2.yaml" \
  apply -f "https://github.com/Networks-it-uc3m/L2S-M/raw/refs/heads/development/deployments/l2sces-deployment.yaml"

echo "✓ Done."
