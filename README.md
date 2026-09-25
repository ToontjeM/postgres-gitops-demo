# Postgres GitOps Demo

Demonstrates managing a PostgreSQL cluster on Kubernetes with GitOps, using
[CloudNativePG](https://cloudnative-pg.io) (CNPG) as the operator, ArgoCD as
the GitOps controller, and a `kind` cluster as the local target environment.

Repo: https://github.com/ToontjeM/gitops

## Running this yourself

ArgoCD only needs to *read* from the repo it's pointed at, but the demo
loop (edit → commit → push → Sync) needs somewhere you can *push* to — and
if you've just cloned this repo, `origin` still points at
`https://github.com/ToontjeM/gitops.git`, which you don't have push access
to. `00-provision.sh` handles this for you:

1. **Prerequisite check.** Before touching anything, it verifies `git`,
   `kind`, `kubectl`, `docker`, `gh`, `curl`, and `git subtree` are
   available, that the Docker daemon is actually reachable (kind needs it
   as its container runtime), and that `gh` is authenticated
   (`gh auth status`). It exits with install/login pointers if any of that
   is missing — nothing is provisioned until these pass.
2. **Remote check.** It reads your clone's `origin`. If `origin` is still
   this repo, it asks:

   > Create a public GitHub repo under your account for just the cluster
   > manifest, using `gh`? [y/N]

   - **Yes** — it creates a new, empty public repo on your GitHub account
     (via `gh repo create`), re-points `origin` at it, and pushes *only*
     the contents of `manifests/` into it as `main` (via
     `git subtree push --prefix=manifests origin main`) — not the rest of
     this demo (scripts, README, kind config, etc). That repo is meant to
     track just the cluster manifest, nothing else.
   - **No** — the script aborts immediately. Nothing is provisioned,
     since ArgoCD would have nothing pushable to sync against. You can
     re-run and answer yes, or point `origin` at a manifests repo of your
     own (`git remote set-url origin <your-repo-url>`) before re-running.

   If `origin` already points somewhere other than this repo (e.g. from a
   previous run, or one you set up yourself), the prompt is skipped
   entirely and that repo is used as-is.
3. **Everything else** (cluster, CNPG, ArgoCD) proceeds as described
   below, with `argocd/application.yaml` templated against whichever repo
   URL `origin` ends up pointing at.

## Layout

- `00-provision.sh` — checks prerequisites, offers to create a personal
  GitHub repo for just the cluster manifest and re-point `origin` at it if
  you're still on this repo's `origin` (see
  [Running this yourself](#running-this-yourself)), creates the `kind`
  cluster, installs the CNPG operator, installs ArgoCD (admin password set
  to `admin` — demo convenience, never do this on a real cluster),
  registers the `postgres-cluster` Application (manual sync — nothing
  deployed yet), and starts a background port-forward so the ArgoCD UI is
  immediately reachable.
- `99-deprovision.sh` — stops that port-forward, deletes the `kind`
  cluster, and if `origin` is a personal manifests repo (not this repo),
  offers to delete that GitHub repo too — or just tells you it's still
  there if it can't (or you'd rather not).
- `kind-config.yaml` — 1 control-plane + 3 worker node topology, so the
  3-instance Postgres cluster below can spread across separate nodes.
- `argocd/application.yaml` — the ArgoCD `Application` pointing at your
  clone's `origin` remote (templated in by `00-provision.sh` at apply
  time), root path (`.`), `main` branch. That remote holds *only* the
  contents of `manifests/`, not this whole demo — see
  [Running this yourself](#running-this-yourself). Applied once by
  `00-provision.sh` as a bootstrap step; it is not itself synced via
  GitOps.
- `manifests/namespace.yaml` — the `postgres-demo` namespace.
- `manifests/postgres-cluster.yaml` — the initial CNPG `Cluster` resource:
  a 3-instance, open source PostgreSQL 17.6 cluster
  (`ghcr.io/cloudnative-pg/postgresql:17.6`). This is the manifest the
  demo evolves via git commits + ArgoCD Sync.

Everything under `manifests/` is GitOps-managed by ArgoCD. Sync is
**manual** (not automated), so a demo step is: edit a manifest → commit →
`git subtree push --prefix=manifests origin main` → click Sync (or
`argocd app sync postgres-cluster`) → watch it apply. A plain
`git push origin main` won't work here — `origin`'s history is just the
split-off `manifests/` contents, unrelated to this repo's own history.

## Usage

```
./00-provision.sh
```

The first run will prompt you to create a personal GitHub repo if needed
(see [Running this yourself](#running-this-yourself)). It then gives you a
ready-to-demo environment:

- kind cluster + CNPG operator installed
- ArgoCD installed, reachable at **https://localhost:8080**
  (user `admin` / password `admin`)
- the `postgres-cluster` Application registered against your repo —
  nothing deployed to `postgres-demo` yet, since sync is manual

If you've made changes under `manifests/`, push just that directory first
so ArgoCD can see them:

```
git subtree push --prefix=manifests origin main
```

Open https://localhost:8080, log in, and click **Sync** on the
`postgres-cluster` Application (or via CLI: `argocd login localhost:8080`
then `argocd app sync postgres-cluster`). Watch it come up:

```
watch -n 1 -c kubectl cnpg get cluster -n postgres-demo --color always
```

Tear everything down when done:

```
./99-deprovision.sh
```

This stops the port-forward and deletes the kind cluster. If `origin` is
a personal manifests repo created for this demo, it also asks whether to
delete that GitHub repo — answering no (or not having `gh` available)
just leaves it in place and says so, it won't be deleted silently.

## Demo idea (next steps)

With the baseline synced, drive the rest of the demo purely through github:
scale `instances`, bump the `imageName` tag, change `resources`, etc. —
commit, `git subtree push --prefix=manifests origin main`, Sync in ArgoCD,
and watch CNPG reconcile the running cluster to match.
