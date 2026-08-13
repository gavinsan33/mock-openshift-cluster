#!/usr/bin/env bash
# Deletes the mock-openshift kind cluster.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

CLUSTER_NAME=mock-openshift
kind delete cluster --name "$CLUSTER_NAME"
