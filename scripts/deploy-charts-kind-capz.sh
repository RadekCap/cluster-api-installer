#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-aso2}
KUBE_CONTEXT="--context=kind-$KIND_CLUSTER_NAME"

${SCRIPT_DIR}/setup-kind-cluster.sh "$KIND_CLUSTER_NAME"
export KUBE_CONTEXT
${SCRIPT_DIR}/deploy-charts.sh charts/cluster-api charts/cluster-api-provider-azure
${SCRIPT_DIR}/wait-for-controllers.sh capi capz


