#!/usr/bin/env bash
# Installs CRDs that GPU-adjacent operators in this environment commonly
# check for optionally (JobSet, KServe InferenceService). Not applied by
# scripts/up.sh by default, since most consumers only need one or neither -
# run the ones you actually need.
set -euo pipefail

install_jobset() {
  # v0.7.2's manifest references gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1
  # for its metrics-proxy sidecar, which 404s - that image was removed
  # from gcr.io upstream. v0.12.0 dropped the sidecar entirely (single
  # manager container), sidestepping the broken reference.
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/jobset/releases/download/v0.12.0/manifests.yaml
  kubectl -n jobset-system rollout status deployment/jobset-controller-manager --timeout=120s
}

install_kserve() {
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
  # kserve.yaml only ships the CRDs/controller, not any actual
  # ClusterServingRuntime objects - without this, every InferenceService
  # fails reconciliation with "no runtime found to support predictor with
  # model type: {<format> <nil>}" for any modelFormat (sklearn, xgboost,
  # etc.), since there's nothing registered to serve it.
  kubectl apply --server-side -f https://github.com/kserve/kserve/releases/download/v0.14.1/kserve-cluster-resources.yaml
  # KServe defaults new InferenceServices to "Serverless" deployment mode,
  # which requires Knative Serving - not installed here (this cluster
  # deliberately skips Knative/Istio to stay lightweight). Without this,
  # every InferenceService's predictor silently never gets a Pod: no
  # error, just an empty status forever. RawDeployment mode uses a plain
  # Deployment/Service instead, no Knative required.
  kubectl -n kserve patch configmap inferenceservice-config --type=merge \
    -p '{"data":{"deploy":"{\"defaultDeploymentMode\": \"RawDeployment\"}"}}'
  kubectl -n kserve rollout restart deployment/kserve-controller-manager
  kubectl -n kserve rollout status deployment/kserve-controller-manager --timeout=120s
}

case "${1:-}" in
  jobset)
    install_jobset
    ;;
  kserve)
    install_kserve
    ;;
  all)
    install_jobset
    install_kserve
    ;;
  *)
    echo "usage: $0 <jobset|kserve|all>" >&2
    exit 1
    ;;
esac
