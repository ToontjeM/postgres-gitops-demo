#!/usr/bin/env bash
#
# Tears down the demo environment: stops the ArgoCD port-forward and
# deletes the kind cluster.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_PID_FILE="${SCRIPT_DIR}/.argocd-port-forward.pid"

if [[ -f "${PF_PID_FILE}" ]]; then
  echo "==> Stopping ArgoCD port-forward"
  kill "$(cat "${PF_PID_FILE}")" 2>/dev/null || true
  rm -f "${PF_PID_FILE}" "${SCRIPT_DIR}/.argocd-port-forward.log"
fi

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "==> Deleting kind cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' does not exist, nothing to do."
fi
