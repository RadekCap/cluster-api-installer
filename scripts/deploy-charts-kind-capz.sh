#!/bin/bash
set -e
KIND_CLUSTER_NAME=aso2
KUBECTL_CONTEXT="kind-$KIND_CLUSTER_NAME"

if ! (kind get clusters 2>/dev/null|grep -q '^'"$KIND_CLUSTER_NAME"'$') ; then 
    kind create cluster --name "$KIND_CLUSTER_NAME"
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m
fi

for CHART in charts/cluster-api \
             charts/cluster-api-provider-azure \
; do
    [ -f $CHART/Chart.yaml ] || continue
    PROJECT=${CHART#charts/}
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo ========= deploy: $CHART
    helm template $CHART --include-crds|kubectl --context "$KUBECTL_CONTEXT" apply -f - --server-side --force-conflicts
    echo
done


for T in capi capz; do
    PROJECT="cluster-api"
    case "$T" in
      capz)
        PROJECT="$PROJECT-provider-azure"
        ;;
    esac
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo "Waiting for ${T} controller:"
    kubectl --context "$KUBECTL_CONTEXT" events -n ${T}-system --watch &
    CH_PID=$!
    kubectl --context "$KUBECTL_CONTEXT" -n ${T}-system wait deployment/${T}-controller-manager --for condition=Available=True  --timeout=10m
    kill $CH_PID
    echo
done


