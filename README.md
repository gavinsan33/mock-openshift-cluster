# mock-openshift-cluster

A lightweight local dev cluster, built on [kind](https://kind.sigs.k8s.io/),
for testing operators/webhooks that target OpenShift + Prometheus + GPU
workloads without needing a real OpenShift cluster or real GPUs.

This is **not** a real OpenShift cluster - it doesn't provide Routes, SCCs,
ClusterOperators, or the Build API. It provides a plain Kubernetes API
server plus:

- **Real [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)**,
  a **scrapeable kube-scheduler**, and the **kubelet's own cAdvisor endpoint**,
  all scraped by a real Prometheus. Since they're the real thing, they report
  whatever's actually in the cluster - fake a GPU workload by creating a
  pod/node with the right requests/labels, not by hand-writing metric values:
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
  - `container_cpu_usage_seconds_total`/`container_memory_working_set_bytes`/
    `container_network_{receive,transmit}_bytes_total` come from every node's
    kubelet cAdvisor endpoint, scraped through the API server's node proxy
    (`kubernetes-cadvisor` job in `manifests/prometheus/configmap.yaml`) since
    kind's kubelet has no directly reachable Service either - real per-pod
    resource usage, not mocked.
- **Auth-gated Prometheus** (`manifests/prometheus/`) - the query API sits behind a
  [kube-rbac-proxy](https://github.com/brancz/kube-rbac-proxy) sidecar requiring a
  valid ServiceAccount bearer token, same as real OpenShift's Thanos Querier. A
  `cluster-monitoring-view` ClusterRole is provided under that exact name so any
  project's RBAC that already binds to it by name against a real cluster (e.g.
  aibom-webhook-service, gpu-quota-operator) grants real access here too, with no
  mock-cluster-specific override needed. Plain HTTP, not HTTPS - this exercises the
  auth path a client already has to handle gracefully when absent, not the separate
  TLS-trust path, which would otherwise require also mocking a service-ca bundle.
  Port-forwarding and querying anonymously from your host no longer works - point an
  in-cluster ServiceAccount at it (or curl from a pod) with `-H "Authorization: Bearer
  $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"`.
- **A mock DCGM exporter** (`manifests/mock-dcgm-exporter/`) - a static
  `/metrics` endpoint serving `DCGM_FI_DEV_*`-shaped series, for testing
  queries that need DCGM data specifically rather than kube-scheduler
  reservation data. Edit `manifests/mock-dcgm-exporter/deployment.yaml`'s
  ConfigMap to change the fake values or the `exported_namespace`/
  `exported_pod` labels to match a real pod you're testing against.
  `manifests/prometheus/configmap.yaml`'s `prometheus-rules` ConfigMap
  layers `nerc:dcgm_{gpu_util,fb_used,power_usage}:avg5m` recording rules on
  top of these raw series (`avg_over_time`, no aggregation - every label,
  including `exported_pod`, passes through unchanged) for projects that query
  those NERC-style rollup names rather than the raw `DCGM_FI_DEV_*` metrics
  directly.
- **A recipe to fake GPU node capacity** (`just patch-gpu-node`) - patches a
  kind node's `status.capacity`/`allocatable` so `nvidia.com/gpu`-requesting
  pods actually schedule, without the NVIDIA device plugin or real GPU
  hardware. Cumulative (`add`/`remove` adjust the existing count instead of
  clobbering it) and defaults to the current node unless one is given.

## Usage

Recipes are run with [`just`](https://just.systems/) - if it's not already
installed, run `make install-just` once. Then:

```sh
just up                       # create the kind cluster, install KSM + scheduler-metrics + mock DCGM + Prometheus
just patch-gpu-node add                            # add 1 fake GPU (default) to the current node
just patch-gpu-node add 4                          # add 4 more fake GPUs, cumulative with whatever's already there
just patch-gpu-node remove 2                       # remove 2 fake GPUs (clamped at 0)
just patch-gpu-node set 8                          # pin the node's fake GPU count to exactly 8
just patch-gpu-node add 4 --node=worker2 --product=CUSTOM  # target a specific node/product label
just apply-examples           # a demo namespace + GPU-requesting Deployment
```

Run `just` with no arguments to see the full recipe list.

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
- `scripts/` - `up.sh` / `down.sh` / `lib.sh` (shared podman/docker detection)
- `manifests/kube-state-metrics/` - real KSM, scoped to pods/nodes RBAC only
- `manifests/kube-scheduler-metrics/` - Service + RBAC exposing
  kube-scheduler's `/metrics/resources` endpoint
- `manifests/mock-dcgm-exporter/` - static DCGM-shaped `/metrics` endpoint
- `manifests/prometheus/` - Prometheus scraping all of the above, fronted by kube-rbac-proxy for auth
- `manifests/optional-crds/` - fetch-on-demand JobSet/KServe CRDs
- `examples/` - a sample GPU-requesting namespace/Deployment to reconcile against

## Using this from another project

Clone alongside your project and reference it from a Makefile/justfile
target, e.g.:

```
[group('cluster')]
dev-cluster:
    just -f ../mock-openshift-cluster/justfile up
    just -f ../mock-openshift-cluster/justfile patch-gpu-node add
```

Then layer your project's own CRDs/RBAC/sample workloads on top with a
normal `kubectl apply -f`.
