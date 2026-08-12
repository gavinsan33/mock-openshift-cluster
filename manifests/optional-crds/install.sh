#!/usr/bin/env bash
# Installs CRDs that GPU-adjacent operators in this environment commonly
# check for optionally (JobSet, KServe InferenceService). Not applied by
# scripts/up.sh by default, since most consumers only need one or neither -
# run the ones you actually need.
set -euo pipefail

case "${1:-}" in
  jobset)
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/jobset/releases/download/v0.7.2/manifests.yaml
    ;;
  kserve)
    kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.14.1/kserve.yaml
    ;;
  *)
    echo "usage: $0 <jobset|kserve>" >&2
    exit 1
    ;;
esac
