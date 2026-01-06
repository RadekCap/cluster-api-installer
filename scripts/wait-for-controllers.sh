#!/bin/bash
set -e

# This script waits for CAPI/CAPZ controllers to be ready
# Can be used standalone or called by other scripts
#
# Usage:
#   ./wait-for-controllers.sh [controller1] [controller2] ...
#
# Environment variables:
#   PROJECT_ONLY - If set, only wait for controllers matching this project name
#   KUBE_CONTEXT - kubectl context flags (e.g., "--context=kind-kind")
#   CONTROLLERS - Space-separated list of controllers (default: capi capz)

# Default controllers if none specified
DEFAULT_CONTROLLERS="capi capz"

# Use provided controllers or command line args or defaults
if [ $# -gt 0 ]; then
    CONTROLLER_LIST="$@"
elif [ -n "$CONTROLLERS" ]; then
    CONTROLLER_LIST="$CONTROLLERS"
else
    CONTROLLER_LIST="$DEFAULT_CONTROLLERS"
fi

for T in $CONTROLLER_LIST; do
    PROJECT="cluster-api"
    case "$T" in
      capz)
        PROJECT="$PROJECT-provider-azure"
        ;;
    esac
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo "Waiting for ${T} controller:"
    kubectl $KUBE_CONTEXT events -n ${T}-system --watch &
    CH_PID=$!
    kubectl $KUBE_CONTEXT -n ${T}-system wait deployment/${T}-controller-manager --for condition=Available=True  --timeout=10m
    kill $CH_PID
    echo
done
