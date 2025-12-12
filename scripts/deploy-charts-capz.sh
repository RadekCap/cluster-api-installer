#!/bin/bash
set -e

if [ -n "$USE_KIND" ] ; then
    CHART_SUFFIX="-k8s"
    KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-aso2}
    KUBE_CONTEXT="--context=kind-$KIND_CLUSTER_NAME"
    
    if ! (kind get clusters 2>/dev/null|grep -q '^'"$KIND_CLUSTER_NAME"'$') ; then 
        kind create cluster --name "$KIND_CLUSTER_NAME" --image="kindest/node:v1.31.0"
        helm repo add jetstack https://charts.jetstack.io --force-update
        helm repo update
        helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m
    fi
else
    OCP_CONTEXT=${OCP_CONTEXT:-crc-admin}
    KUBE_CONTEXT="--context=$OCP_CONTEXT"
fi

for CHART in charts/cluster-api"$CHART_SUFFIX" \
             charts/cluster-api-provider-azure"$CHART_SUFFIX" \
; do
    [ -f $CHART/Chart.yaml ] || continue
    PROJECT=${CHART#charts/}
    PROJECT=${PROJECT%-k8s}
    case "$PROJECT" in
      cluster-api)
        NAMESPACE="capi-system"
        ;;
      cluster-api-provider-azure)
        NAMESPACE="capz-system"
        ;;
    esac

    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo ========= deploy: $CHART
    echo "        PROJECT: $PROJECT"
    echo "      NAMESPACE: $NAMESPACE"
    helm template $CHART --include-crds --namespace "$NAMESPACE" |kubectl $KUBE_CONTEXT apply -f - --server-side --force-conflicts
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
    kubectl $KUBE_CONTEXT events -n ${T}-system --watch &
    CH_PID=$!
    kubectl $KUBE_CONTEXT -n ${T}-system wait deployment/${T}-controller-manager --for condition=Available=True  --timeout=10m
    if [ "${T}" = capz ] ; then
        kubectl $KUBE_CONTEXT -n ${T}-system wait deployment/azureserviceoperator-controller-manager --for condition=Available=True  --timeout=10m
    fi
    kill $CH_PID
    echo
done



