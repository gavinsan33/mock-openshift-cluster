#!/usr/bin/env bash
# Deletes the mock-openshift kind cluster.
set -euo pipefail

CLUSTER_NAME=mock-openshift
kind delete cluster --name "$CLUSTER_NAME"
