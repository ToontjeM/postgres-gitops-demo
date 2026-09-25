#!/usr/bin/env bash
#
# Provisions the demo environment:
#   1. a local kind Kubernetes cluster
#   2. the CloudNativePG (CNPG) operator
#   3. ArgoCD, with its admin password set to 'admin' (demo convenience —
#      do not reuse this outside a throwaway local cluster), bootstrapped
#      with an Application pointed at this repo's manifests/ directory
#      (manual sync — nothing is deployed yet)
#   4. a background port-forward so the ArgoCD UI is reachable straight away
#
# It does NOT deploy the Postgres cluster itself — that happens via a git
# push plus an ArgoCD Sync, which is the actual demo.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml"
ARGOCD_UI_PORT="8080"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_PID_FILE="${SCRIPT_DIR}/.argocd-port-forward.pid"
PF_LOG_FILE="${SCRIPT_DIR}/.argocd-port-forward.log"

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

echo "==> Setting the ArgoCD admin password to 'admin'"
ADMIN_BCRYPT_HASH="$(kubectl exec -n argocd deploy/argocd-server -- argocd account bcrypt --password admin)"
kubectl -n argocd patch secret argocd-secret \
  -p "{\"stringData\": {\"admin.password\": \"${ADMIN_BCRYPT_HASH}\", \"admin.passwordMtime\": \"$(date -u +%FT%TZ)\"}}"

echo "==> Registering the postgres-cluster Application with ArgoCD"
kubectl apply -f "${SCRIPT_DIR}/argocd/application.yaml"

echo "==> Starting background port-forward to the ArgoCD UI"
if [[ -f "${PF_PID_FILE}" ]] && kill -0 "$(cat "${PF_PID_FILE}")" 2>/dev/null; then
  kill "$(cat "${PF_PID_FILE}")"
fi
nohup kubectl port-forward svc/argocd-server -n argocd "${ARGOCD_UI_PORT}:443" \
  > "${PF_LOG_FILE}" 2>&1 &
echo $! > "${PF_PID_FILE}"

echo "==> Waiting for the port-forward to accept connections"
for _ in $(seq 1 30); do
  if curl -sk --max-time 1 "https://localhost:${ARGOCD_UI_PORT}" -o /dev/null; then
    break
  fi
  sleep 1
done

cat <<EOF

Environment ready.

Context:     kind-${CLUSTER_NAME}
CNPG:        cnpg-system/cnpg-controller-manager
ArgoCD UI:   https://localhost:${ARGOCD_UI_PORT}  (user: admin / password: admin)
Application: 'postgres-cluster' registered against manifests/ on main, not yet synced

Nothing is deployed to postgres-demo yet. To run the demo:

  1. git push -u origin main   (if you haven't already)
  2. Open https://localhost:${ARGOCD_UI_PORT} and log in
  3. Sync the 'postgres-cluster' Application (UI button, or:
       argocd app sync postgres-cluster)
EOF
