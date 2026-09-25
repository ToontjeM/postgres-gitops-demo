# Postgres GitOps Demo

Demonstrates managing a PostgreSQL cluster on Kubernetes with GitOps, using
[CloudNativePG](https://cloudnative-pg.io) (CNPG) as the operator, ArgoCD as
the GitOps controller, and a `kind` cluster as the local target environment.

Repo: https://github.com/ToontjeM/gitops

## Layout

- `00-provision.sh` — creates the `kind` cluster, installs the CNPG
  operator, installs ArgoCD, and registers the `postgres-cluster`
  Application (manual sync — nothing deployed yet).
- `99-deprovision.sh` — deletes the `kind` cluster.
- `kind-config.yaml` — 1 control-plane + 3 worker node topology, so the
  3-instance Postgres cluster below can spread across separate nodes.
- `argocd/application.yaml` — the ArgoCD `Application` pointing at this
  repo's `manifests/` directory on `main`. Applied once by `00-provision.sh`
  as a bootstrap step; it is not itself synced via GitOps.
- `manifests/namespace.yaml` — the `postgres-demo` namespace.
- `manifests/postgres-cluster.yaml` — the initial CNPG `Cluster` resource:
  a 3-instance, open source PostgreSQL 17.6 cluster
  (`ghcr.io/cloudnative-pg/postgresql:17.6`). This is the manifest the
  demo evolves via git commits + ArgoCD Sync.

Everything under `manifests/` is GitOps-managed by ArgoCD. Sync is
**manual** (not automated), so a demo step is: edit a manifest → commit →
push → click Sync (or `argocd app sync postgres-cluster`) → watch it apply.

## Usage

```
./00-provision.sh
```

This gives you: a running kind cluster, the CNPG operator, ArgoCD, and an
ArgoCD `Application` registered against this repo — but nothing deployed to
`postgres-demo` yet, since sync is manual.

Push this repo to GitHub first (ArgoCD needs to be able to clone it):

```
git push -u origin main
```

Then open the ArgoCD UI and sync:

```
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080          # user: admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Click **Sync** on the `postgres-cluster` Application, or via CLI:

```
argocd login localhost:8080
argocd app sync postgres-cluster
kubectl get cluster -n postgres-demo -w
```

Tear everything down when done:

```
./99-deprovision.sh
```

## Demo idea (next steps)

With the baseline synced, drive the rest of the demo purely through git:
scale `instances`, bump the `imageName` tag, change `resources`, etc. —
commit, push, Sync in ArgoCD, and watch CNPG reconcile the running cluster
to match.
