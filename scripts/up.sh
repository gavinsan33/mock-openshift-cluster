#!/usr/bin/env bash
# Creates the mock-openshift kind cluster and installs kube-state-metrics,
# a scrapeable kube-scheduler (for kube_pod_resource_request/_limit), a mock
# DCGM exporter, and Prometheus scraping all three. Real OpenShift-only
# pieces (Routes, SCCs, ClusterOperators, the Build API) are NOT provided -
# this mimics "a Kubernetes cluster with GPU-shaped metrics", not OpenShift
# itself. Safe to re-run; every step is idempotent.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

CLUSTER_NAME=mock-openshift

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "kind cluster '$CLUSTER_NAME' already exists - skipping create"
else
  kind create cluster --config kind-config.yaml
fi

kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/kube-state-metrics/
kubectl apply -f manifests/mock-dcgm-exporter/
kubectl apply -f manifests/kube-scheduler-metrics/
kubectl apply -f manifests/prometheus/

echo "waiting for kube-state-metrics, mock-dcgm-exporter, and prometheus to be ready..."
kubectl -n monitoring rollout status deployment/kube-state-metrics --timeout=120s
kubectl -n monitoring rollout status deployment/mock-dcgm-exporter --timeout=120s
kubectl -n monitoring rollout status deployment/prometheus --timeout=120s

echo
echo "Cluster ready. To point a locally-run operator/webhook at Prometheus:"
echo "  kubectl -n monitoring port-forward svc/prometheus 9090:9090"
echo
echo "To make a node schedule fake GPU workloads:"
echo "  just patch-gpu-node <node-name> [gpu-count] [product-label]"
