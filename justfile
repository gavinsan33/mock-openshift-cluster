# Run `just` with no arguments to see this list.
default:
    @just --list

cluster_name := "mock-openshift"

# --- Cluster lifecycle ---------------------------------------------------

# Create the kind cluster and install KSM + scheduler-metrics + mock DCGM + Prometheus. Safe to re-run.
[group('cluster')]
up:
    ./scripts/up.sh

[group('cluster')]
down:
    ./scripts/down.sh

# Fake GPU capacity on a node so nvidia.com/gpu-requesting pods can schedule.
# Usage: just patch-gpu-node [node-name] [gpu-count] [product-label]
[group('cluster')]
patch-gpu-node *args:
    ./scripts/patch-gpu-node.sh {{ args }}

# Apply the demo namespace + GPU-requesting Deployment from examples/.
[group('cluster')]
apply-examples:
    kubectl apply -f examples/

# --- Optional CRDs --------------------------------------------------------

# Install optional CRDs (jobset or kserve) that GPU-adjacent operators commonly check for.
[group('crds')]
install-crds target:
    ./manifests/optional-crds/install.sh {{ target }}
