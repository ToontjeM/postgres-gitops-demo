#!/usr/bin/env bash
#
# Provisions the demo environment:
#   1. a local kind Kubernetes cluster
#   2. the CloudNativePG (CNPG) operator
#
# It does NOT deploy the Postgres cluster or any GitOps controller (ArgoCD/Flux) —
# those are the actual demo steps, applied on top of this baseline.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Creating kind cluster '${CLUSTER_NAME}'"
if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "    Cluster '${CLUSTER_NAME}' already exists, skipping creation."
else
  kind create cluster --name "${CLUSTER_NAME}" --config "${SCRIPT_DIR}/kind-config.yaml"
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "==> Installing the CloudNativePG operator"
kubectl apply --server-side -f "${CNPG_MANIFEST}"

echo "==> Waiting for the CNPG operator to become ready"
kubectl rollout status deployment cnpg-controller-manager -n cnpg-system --timeout=180s

echo "==> Creating the postgres-demo namespace"
kubectl apply -f "${SCRIPT_DIR}/manifests/namespace.yaml"

cat <<EOF

Environment ready.

Context:   kind-${CLUSTER_NAME}
Operator:  cnpg-system/cnpg-controller-manager

Next: apply manifests/postgres-cluster.yaml (directly, or via a GitOps
controller pointed at this repo) to deploy the initial Postgres cluster.
EOF
