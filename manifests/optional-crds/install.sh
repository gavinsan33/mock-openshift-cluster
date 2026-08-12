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
    # kserve.yaml provisions its webhook's TLS cert via cert-manager's
    # Certificate/Issuer CRDs - without cert-manager already installed,
    # those two resources fail to apply and kserve-controller-manager hangs
    # forever in ContainerCreating waiting on a Secret
    # (kserve-webhook-server-cert) that never gets created.
    if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
      echo "installing cert-manager (kserve's webhook cert depends on it)..."
      kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
      kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=120s
    fi
    kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.14.1/kserve.yaml
    kubectl -n kserve rollout status deployment/kserve-controller-manager --timeout=120s
    ;;
  *)
    echo "usage: $0 <jobset|kserve>" >&2
    exit 1
    ;;
esac
