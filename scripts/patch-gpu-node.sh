#!/usr/bin/env bash
# Fakes GPU capacity on a kind node so nvidia.com/gpu-requesting pods can
# actually schedule, without a real GPU or the NVIDIA device plugin. Also
# labels the node with the NFD/GPU-Operator-style product label that
# kube-state-metrics' kube_node_labels metric exposes, since GPU-hours
# queries typically join on it.
#
# Usage: patch-gpu-node.sh [node-name] [gpu-count] [product-label]
#   node-name:     defaults to the first node found
#   gpu-count:     defaults to 4
#   product-label: defaults to NVIDIA-A100-SXM4-80GB
set -euo pipefail

NODE="${1:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')}"
GPU_COUNT="${2:-4}"
PRODUCT="${3:-NVIDIA-A100-SXM4-80GB}"

kubectl label node "$NODE" nvidia.com/gpu.product="$PRODUCT" --overwrite

kubectl patch node "$NODE" --subresource=status --type=merge -p "$(cat <<EOF
{
  "status": {
    "capacity": {"nvidia.com/gpu": "$GPU_COUNT"},
    "allocatable": {"nvidia.com/gpu": "$GPU_COUNT"}
  }
}
EOF
)"

echo "node $NODE now advertises $GPU_COUNT nvidia.com/gpu, labeled product=$PRODUCT"
