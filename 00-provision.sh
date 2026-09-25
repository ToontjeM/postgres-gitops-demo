#!/usr/bin/env bash
#
# Provisions the demo environment:
#   1. a local kind Kubernetes cluster
#   2. the CloudNativePG (CNPG) operator
#   3. ArgoCD, bootstrapped with an Application pointed at this repo's
#      manifests/ directory (manual sync — nothing is deployed yet)
#
# It does NOT deploy the Postgres cluster itself — that happens via a git
# push plus an ArgoCD Sync, which is the actual demo.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml"
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

echo "==> Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd -f "${ARGOCD_MANIFEST}"

echo "==> Waiting for the ArgoCD API server to become ready"
kubectl rollout status deployment argocd-server -n argocd --timeout=300s

echo "==> Registering the postgres-cluster Application with ArgoCD"
kubectl apply -f "${SCRIPT_DIR}/argocd/application.yaml"

cat <<EOF

Environment ready.

Context:     kind-${CLUSTER_NAME}
CNPG:        cnpg-system/cnpg-controller-manager
ArgoCD:      argocd/argocd-server (Application 'postgres-cluster' registered, not yet synced)

Nothing is deployed to postgres-demo yet. To run the demo:

  1. Push this repo to https://github.com/ToontjeM/gitops.git (branch: main)
  2. Open the ArgoCD UI:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
       open https://localhost:8080   (user: admin)
       kubectl -n argocd get secret argocd-initial-admin-secret \\
         -o jsonpath='{.data.password}' | base64 -d; echo
  3. Sync the 'postgres-cluster' Application (UI button, or:
       argocd app sync postgres-cluster)
EOF
