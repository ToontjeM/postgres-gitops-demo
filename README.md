# Postgres GitOps Demo

Demonstrates managing a PostgreSQL cluster on Kubernetes with GitOps, using
[CloudNativePG](https://cloudnative-pg.io) (CNPG) as the operator and a
`kind` cluster as the local target environment.

## Layout

- `00-provision.sh` — creates the `kind` cluster and installs the CNPG operator.
- `99-deprovision.sh` — deletes the `kind` cluster.
- `kind-config.yaml` — 1 control-plane + 3 worker node topology, so the
  3-instance Postgres cluster below can spread across separate nodes.
- `manifests/namespace.yaml` — the `postgres-demo` namespace.
- `manifests/postgres-cluster.yaml` — the initial CNPG `Cluster` resource:
  a 3-instance, open source PostgreSQL 17.6 cluster
  (`ghcr.io/cloudnative-pg/postgresql:17.6`). This is the manifest the
  actual GitOps demo will deploy and evolve.

## Usage

```
./00-provision.sh
```

This gives you a bare environment: a running kind cluster with the CNPG
operator installed, but no Postgres cluster deployed yet.

To manually deploy the initial cluster (without GitOps, e.g. to sanity-check
the manifest):

```
kubectl apply -f manifests/postgres-cluster.yaml
kubectl get cluster -n postgres-demo -w
```

Tear everything down when done:

```
./99-deprovision.sh
```

## Next steps (future demo parts)

This first setup deliberately stops short of installing a GitOps controller.
Subsequent steps will add ArgoCD or Flux, point it at this repo, and use it
to deploy and then evolve `manifests/postgres-cluster.yaml` (scaling
instances, changing the Postgres version, tuning resources, etc.) purely
through git commits.
