#!/usr/bin/env bash
#
# Provisions the demo environment. There are two repos in play:
#   - this repo (gitops) — the demo tooling. Everyone clones/pulls it;
#     only Ton can push to it. This script never touches its 'origin'.
#   - a personal "postgres-gitops-demo" repo, created in YOUR GitHub
#     account with full access for you, holding only the contents of
#     manifests/ (not the rest of this demo). ArgoCD tracks that repo, and
#     you push to it via a local remote named 'manifests'.
#
# Steps:
#   0. checks for required local tools (git, kind, kubectl, docker, gh,
#      curl, and git-subtree)
#   1. if no local 'manifests' remote is configured yet, offers to create
#      that personal GitHub repo (via `gh`), add it as the 'manifests'
#      remote, and push manifests/ to it (via `git subtree push`) —
#      aborting if declined, since ArgoCD needs it to sync against
#   2. a local kind Kubernetes cluster
#   3. the CloudNativePG (CNPG) operator
#   4. ArgoCD, with its admin password set to 'admin' (demo convenience —
#      do not reuse this outside a throwaway local cluster), bootstrapped
#      with an Application pointed at the root of your manifests repo
#      (manual sync — nothing is deployed yet)
#   5. a background port-forward so the ArgoCD UI is reachable straight away
#
# It does NOT deploy the Postgres cluster itself — that happens via a git
# push plus an ArgoCD Sync, which is the actual demo.
set -euo pipefail

CLUSTER_NAME="pg-gitops-demo"
CNPG_MANIFEST="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml"
ARGOCD_UI_PORT="8080"
MANIFESTS_REMOTE="manifests"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_PID_FILE="${SCRIPT_DIR}/.argocd-port-forward.pid"
PF_LOG_FILE="${SCRIPT_DIR}/.argocd-port-forward.log"

echo "==> Checking prerequisites"
MISSING_TOOLS=()
for tool in git kind kubectl docker gh curl; do
  command -v "${tool}" >/dev/null 2>&1 || MISSING_TOOLS+=("${tool}")
done
if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
  echo "    error: missing required tool(s): ${MISSING_TOOLS[*]}"
  echo "    install them and re-run this script. See:"
  echo "      git    https://git-scm.com/downloads"
  echo "      kind   https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
  echo "      kubectl https://kubernetes.io/docs/tasks/tools/"
  echo "      docker https://docs.docker.com/get-docker/  (kind's container runtime)"
  echo "      gh     https://cli.github.com/"
  exit 1
fi

if ! git subtree --help >/dev/null 2>&1; then
  echo "    error: 'git subtree' isn't available (needed to push only manifests/,"
  echo "    not the whole demo, to your personal repo). It ships with most git"
  echo "    distributions (e.g. Homebrew git, most Linux distro packages) but not"
  echo "    all minimal installs — reinstall git with contrib/subtree included."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "    error: docker is installed but not reachable — is the daemon (or Docker Desktop) running?"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "    error: gh is installed but not logged in. Run 'gh auth login' first."
  exit 1
fi

if ! git -C "${SCRIPT_DIR}" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "    error: $(pwd) is not a git checkout — clone this repo normally and re-run."
  exit 1
fi

echo "==> Checking for a personal manifests repo"
MANIFESTS_URL="$(git -C "${SCRIPT_DIR}" remote get-url "${MANIFESTS_REMOTE}" 2>/dev/null || true)"
if [[ -z "${MANIFESTS_URL}" ]]; then
  cat <<EOF

No '${MANIFESTS_REMOTE}' remote is configured yet. This repo (gitops) is
demo tooling you can only pull from — ArgoCD needs a separate repo you
have full push access to, holding only the cluster manifest.
EOF
  read -r -p "Create a public GitHub repo under your account for just the cluster manifest, using 'gh'? [y/N] " CREATE_REPO_REPLY
  if [[ ! "${CREATE_REPO_REPLY}" =~ ^[Yy]$ ]]; then
    echo "    Aborting — without a repo you can push to, ArgoCD sync won't work for you."
    echo "    Re-run and answer yes, or add your own manifests repo as the"
    echo "    '${MANIFESTS_REMOTE}' remote ('git remote add ${MANIFESTS_REMOTE} <your-repo-url>')"
    echo "    before re-running."
    exit 1
  fi

  GH_USER="$(gh api user -q .login)"
  REPO_NAME="postgres-gitops-demo"
  if gh repo view "${GH_USER}/${REPO_NAME}" >/dev/null 2>&1; then
    REPO_NAME="postgres-gitops-demo-$(date +%s)"
  fi

  echo "==> Creating GitHub repo '${GH_USER}/${REPO_NAME}'"
  gh repo create "${REPO_NAME}" --public --description "Cluster manifest for the Postgres GitOps demo"

  MANIFESTS_URL="https://github.com/${GH_USER}/${REPO_NAME}.git"
  echo "==> Adding '${MANIFESTS_REMOTE}' remote (${MANIFESTS_URL}) and pushing manifests/ only"
  git -C "${SCRIPT_DIR}" remote add "${MANIFESTS_REMOTE}" "${MANIFESTS_URL}"
  git -C "${SCRIPT_DIR}" subtree push --prefix=manifests "${MANIFESTS_REMOTE}" main
else
  # Normalize an SSH remote (git@github.com:user/repo.git) to HTTPS, since
  # ArgoCD's default cluster config has no SSH known_hosts/deploy key set up.
  MANIFESTS_URL="$(sed -E 's#^git@([^:]+):#https://\1/#' <<<"${MANIFESTS_URL}")"
fi
echo "    Using manifests repo: ${MANIFESTS_URL}"

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
sed "s#__REPO_URL__#${MANIFESTS_URL}#" "${SCRIPT_DIR}/argocd/application.yaml" | kubectl apply -f -

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
Application: 'postgres-cluster' registered against ${MANIFESTS_URL} on main, not yet synced

Nothing is deployed to postgres-demo yet. To run the demo:

  1. Edit a file under manifests/, commit it, then push just that directory
     (not the whole demo) to your manifests repo:
       git subtree push --prefix=manifests ${MANIFESTS_REMOTE} main
  2. Open https://localhost:${ARGOCD_UI_PORT} and log in
  3. Sync the 'postgres-cluster' Application (UI button, or:
       argocd app sync postgres-cluster)
EOF
