# mock-openshift-cluster

A lightweight local dev cluster, built on [kind](https://kind.sigs.k8s.io/),
for testing operators/webhooks that target OpenShift + Prometheus + GPU
workloads without needing a real OpenShift cluster or real GPUs.

This is **not** a real OpenShift cluster - it doesn't provide Routes, SCCs,
ClusterOperators, or the Build API. It provides a plain Kubernetes API
server plus:

- **Real [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)**
  and a **scrapeable kube-scheduler**, both scraped by a real Prometheus.
  Since they're the real thing, they report whatever's actually in the
  cluster - fake a GPU workload by creating a pod/node with the right
  requests/labels, not by hand-writing metric values:
  - `kube_node_labels` (from real node labels) comes from kube-state-metrics.
  - `kube_pod_resource_request`/`kube_pod_resource_limit` (per-pod GPU
    reservation) come from **kube-scheduler's own `/metrics/resources`
    endpoint** (KEP-1748) - NOT kube-state-metrics, which only exposes the
    per-*container* `kube_pod_container_resource_requests`/`_limits`.
    `manifests/kube-scheduler-metrics/` exposes kind's scheduler (normally
    bound to `127.0.0.1` only - see `kind-config.yaml`'s
    `kubeadmConfigPatches`) via a Service, gated by the
    `/metrics/resources` nonResourceURL RBAC a real cluster's monitoring
    stack would also need.
- **A mock DCGM exporter** (`manifests/mock-dcgm-exporter/`) - a static
  `/metrics` endpoint serving `DCGM_FI_DEV_*`-shaped series, for testing
  queries that need DCGM data specifically rather than kube-scheduler
  reservation data. Edit `manifests/mock-dcgm-exporter/deployment.yaml`'s
  ConfigMap to change the fake values.
- **A script to fake GPU node capacity** (`scripts/patch-gpu-node.sh`) -
  patches a kind node's `status.capacity`/`allocatable` so
  `nvidia.com/gpu`-requesting pods actually schedule, without the NVIDIA
  device plugin or real GPU hardware.

## Usage

Recipes are run with [`just`](https://just.systems/) - if it's not already
installed, run `make install-just` once. Then:

```sh
just up               # create the kind cluster, install KSM + scheduler-metrics + mock DCGM + Prometheus
just patch-gpu-node    # fake GPU capacity on the first node
just apply-examples    # a demo namespace + GPU-requesting Deployment
```

Run `just` with no arguments to see the full recipe list.

Point a locally-run operator/webhook at Prometheus:

```sh
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# then run your operator with --prometheus-url=http://localhost:9090
```

Tear down:

```sh
just down
```

## Optional CRDs

Some operators check for CRDs beyond core Kubernetes (e.g. JobSet,
KServe's InferenceService). These aren't installed by `just up` by default -
install only what your project needs:

```sh
just install-crds jobset
just install-crds kserve
just install-crds all      # both
```

`kserve` also installs cert-manager first (kserve's webhook TLS cert depends
on it) - skipped automatically if cert-manager's CRDs are already present.

If `kserve-controller-manager` crash-loops with `"too many open files"`,
that's a host-level Linux inotify limit, not a cluster problem - kind's
containers share the host's inotify watch/instance limits, and the defaults
are often too low for a watch-heavy controller-runtime manager:

```sh
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=8192
```

Then delete the crashing pod so it restarts clean:
`kubectl -n kserve delete pod -l control-plane=kserve-controller-manager`

## Layout

- `kind-config.yaml` - single-node kind cluster definition, including the
  `kubeadmConfigPatches` that opens up kube-scheduler's metrics port
- `justfile` - recipes for cluster lifecycle (`up`/`down`/`patch-gpu-node`/`install-crds`); `Makefile` only bootstraps `just` itself
- `scripts/` - `up.sh` / `down.sh` / `patch-gpu-node.sh` / `lib.sh` (shared podman/docker detection)
- `manifests/kube-state-metrics/` - real KSM, scoped to pods/nodes RBAC only
- `manifests/kube-scheduler-metrics/` - Service + RBAC exposing
  kube-scheduler's `/metrics/resources` endpoint
- `manifests/mock-dcgm-exporter/` - static DCGM-shaped `/metrics` endpoint
- `manifests/prometheus/` - Prometheus scraping all of the above
- `manifests/optional-crds/` - fetch-on-demand JobSet/KServe CRDs
- `examples/` - a sample GPU-requesting namespace/Deployment to reconcile against

## Using this from another project

Clone alongside your project and reference it from a Makefile/justfile
target, e.g.:

```
[group('cluster')]
dev-cluster:
    just -f ../mock-openshift-cluster/justfile up
    just -f ../mock-openshift-cluster/justfile patch-gpu-node
```

Then layer your project's own CRDs/RBAC/sample workloads on top with a
normal `kubectl apply -f`.
