#!/usr/bin/env bash
#
# Tears down the demo environment: stops the ArgoCD port-forward, deletes
# the kind cluster, and offers to delete the personal GitHub repo that
# 00-provision.sh created (as the local 'manifests' remote) to hold the
# cluster manifest — that repo lives outside the kind cluster, so it
# survives on its own unless removed here.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
MANIFESTS_REMOTE="manifests"
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

MANIFESTS_URL="$(git -C "${SCRIPT_DIR}" remote get-url "${MANIFESTS_REMOTE}" 2>/dev/null || true)"
if [[ -n "${MANIFESTS_URL}" ]]; then
  MANIFESTS_URL="$(sed -E 's#^git@([^:]+):#https://\1/#' <<<"${MANIFESTS_URL}")"
  echo
  echo "Your personal cluster-manifest repo is still around:"
  echo "  ${MANIFESTS_URL}"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    read -r -p "Delete that GitHub repo too? [y/N] " DELETE_REPO_REPLY
    if [[ "${DELETE_REPO_REPLY}" =~ ^[Yy]$ ]]; then
      REPO_SLUG="$(sed -E 's#^https://github\.com/##; s#\.git$##' <<<"${MANIFESTS_URL}")"
      echo "==> Deleting GitHub repo '${REPO_SLUG}'"
      gh repo delete "${REPO_SLUG}" --yes
      git -C "${SCRIPT_DIR}" remote remove "${MANIFESTS_REMOTE}"
    else
      echo "    Leaving it in place — delete it yourself later if you don't need it."
    fi
  else
    echo "    ('gh' unavailable or not logged in — delete it yourself on GitHub"
    echo "    if you don't need it, it was left untouched.)"
  fi
fi
