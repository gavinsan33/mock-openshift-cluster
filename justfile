# Run `just` with no arguments to see this list.
default:
    @just --list

cluster_name := "mock-openshift"

# --- Cluster lifecycle ---------------------------------------------------

# provider defaults to auto-detect (scripts/lib.sh: docker unless its daemon is
# unreachable). Pass it explicitly - `just up docker` / `just up podman` - when
# you need to target a specific engine regardless of what's installed, e.g. to
# avoid ending up with two same-named clusters (one per engine) if both are
# present. up/down must be given the same provider, or down will silently
# no-op against the wrong engine and leave the other engine's cluster running.
#
# Create the kind cluster and install KSM + scheduler-metrics + mock DCGM + Prometheus. Safe to re-run.
[group('cluster')]
up provider="":
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{ provider }}" ] && export KIND_EXPERIMENTAL_PROVIDER="{{ provider }}"
    ./scripts/up.sh

[group('cluster')]
down provider="":
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{ provider }}" ] && export KIND_EXPERIMENTAL_PROVIDER="{{ provider }}"
    ./scripts/down.sh

# Usage: just patch-gpu-node <add|remove|set> [count] [--node=x] [--product=x]
#   add:    adjust the current count up by [count] (default 1).
#   remove: adjust the current count down by [count] (default 1), clamped at
#           0. Removing down to 0 clears the product label too.
#   set:    pin the count to exactly [count] (default 4), ignoring whatever's
#           already there.
#   --node:    defaults to the current node (the first node found)
#   --product: defaults to NVIDIA-A100-SXM4-80GB (add/set only)
# Fake GPU capacity on a node: `add`, `remove`, or `set` the nvidia.com/gpu count.
[group('cluster')]
patch-gpu-node action *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ action }}" in
      add) default_count=1 ;;
      remove) default_count=1 ;;
      set) default_count=4 ;;
      *) echo "unknown action '{{ action }}' (expected add, remove, or set)" >&2; exit 1 ;;
    esac

    count=""
    node=""
    product="NVIDIA-A100-SXM4-80GB"
    eval set -- {{ flags }}
    while [ $# -gt 0 ]; do
      case "$1" in
        --node=*) node="${1#--node=}" ;;
        --node) node="$2"; shift ;;
        --product=*) product="${1#--product=}" ;;
        --product) product="$2"; shift ;;
        --*) echo "unknown flag '$1' (expected --node=x or --product=x)" >&2; exit 1 ;;
        *)
          if [ -n "$count" ]; then
            echo "unexpected argument '$1' (count is already '$count')" >&2
            exit 1
          fi
          count="$1"
          ;;
      esac
      shift
    done
    delta="${count:-$default_count}"
    node="${node:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')}"

    current="$(kubectl get node "$node" -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || true)"
    current="${current:-0}"
    case "{{ action }}" in
      add) new=$((current + delta)) ;;
      remove) new=$((current - delta)); [ "$new" -lt 0 ] && new=0 ;;
      set) new="$delta" ;;
    esac
    kubectl patch node "$node" --subresource=status --type=merge -p "$(cat <<EOF
    {
      "status": {
        "capacity": {"nvidia.com/gpu": "$new"},
        "allocatable": {"nvidia.com/gpu": "$new"}
      }
    }
    EOF
    )"
    if [ "$new" -eq 0 ]; then
      kubectl label node "$node" nvidia.com/gpu.product- >/dev/null 2>&1 || true
      echo "node $node now advertises 0 nvidia.com/gpu, product label cleared"
    elif [ "{{ action }}" = "remove" ]; then
      echo "node $node now advertises $new nvidia.com/gpu (was $current), product label unchanged"
    else
      kubectl label node "$node" nvidia.com/gpu.product="$product" --overwrite
      echo "node $node now advertises $new nvidia.com/gpu (was $current), labeled product=$product"
    fi

# Apply the demo namespace + GPU-requesting Deployment from examples/.
[group('cluster')]
apply-examples:
    kubectl apply -f examples/

# --- Optional CRDs --------------------------------------------------------

# Install optional CRDs (jobset or kserve) that GPU-adjacent operators commonly check for.
[group('crds')]
install-crds target:
    ./manifests/optional-crds/install.sh {{ target }}
