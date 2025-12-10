#!/bin/bash
set -e

# This script deploys Helm charts to a Kubernetes cluster
# Can be used standalone or sourced by other scripts
#
# Usage:
#   ./deploy-charts.sh [chart1] [chart2] ...
#
# Environment variables:
#   PROJECT_ONLY - If set, only deploy charts matching this project name
#   KUBE_CONTEXT - kubectl context flags (e.g., "--context=kind-kind")
#   CHARTS - Space-separated list of charts to deploy (default: cluster-api cluster-api-provider-azure)

# Default charts if none specified
DEFAULT_CHARTS="charts/cluster-api
charts/cluster-api-provider-azure"

# Use provided charts or command line args or defaults
if [ $# -gt 0 ]; then
    CHART_LIST="$@"
elif [ -n "$CHARTS" ]; then
    CHART_LIST="$CHARTS"
else
    CHART_LIST="$DEFAULT_CHARTS"
fi

for CHART in $CHART_LIST; do
    [ -f $CHART/Chart.yaml ] || continue
    PROJECT=${CHART#charts/}
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo ========= deploy: $CHART
    helm template $CHART --include-crds|kubectl $KUBE_CONTEXT apply -f - --server-side --force-conflicts
    echo
done
