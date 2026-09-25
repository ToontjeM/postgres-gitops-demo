#!/usr/bin/env bash
#
# Tears down the demo environment by deleting the kind cluster.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "==> Deleting kind cluster '${CLUSTER_NAME}'"
  kind delete cluster --name "${CLUSTER_NAME}"
else
  echo "Cluster '${CLUSTER_NAME}' does not exist, nothing to do."
fi
