#!/bin/bash
set -e
#PROJECT_ONLY=cluster-api-provider-azure
KIND_CLUSTER_NAME=aso2

if ! (kind get clusters 2>/dev/null|grep -q '^'"$KIND_CLUSTER_NAME"'$') ; then 
    kind create cluster --name "$KIND_CLUSTER_NAME"
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m
fi

export AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export AZURE_SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
[ "$AZURE_SUBSCRIPTION_NAME" == "ARO SRE Team - INT (EA Subscription 3)"    ] && export REGION=${REGION:-uksouth}
[ "$AZURE_SUBSCRIPTION_NAME" == "ARO HCP - STAGE testing (EA Subscription)" ] && export REGION=${REGION:-uksouth}
export REGION=${REGION:-westus3}
SP_JSON_FILE="sp-$AZURE_SUBSCRIPTION_ID.json"
if [ ! -f "$SP_JSON_FILE" ] ; then
    let "randomIdentifier=$RANDOM*$RANDOM"
    servicePrincipalName="msdocs-sp-$randomIdentifier"
    roleName="Contributor"
    echo "Creating SP for RBAC with name $servicePrincipalName, with role $roleName and in scopes /subscriptions/$AZURE_SUBSCRIPTION_ID"
    az ad sp create-for-rbac --name $servicePrincipalName --role $roleName --scopes /subscriptions/$AZURE_SUBSCRIPTION_ID > "$SP_JSON_FILE"
fi
export AZURE_TENANT_ID=$(jq -r .tenant "$SP_JSON_FILE")
export AZURE_CLIENT_ID=$(jq -r .appId "$SP_JSON_FILE")
export AZURE_CLIENT_SECRET=$(jq -r .password "$SP_JSON_FILE")

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
 name: aso-credential
 namespace: default
stringData:
 AZURE_SUBSCRIPTION_ID: "$AZURE_SUBSCRIPTION_ID"
 AZURE_TENANT_ID: "$AZURE_TENANT_ID"
 AZURE_CLIENT_ID: "$AZURE_CLIENT_ID"
 AZURE_CLIENT_SECRET: "$AZURE_CLIENT_SECRET"
EOF

for CHART in charts/cluster-api \
             charts/cluster-api-provider-azure \
; do
    [ -f $CHART/Chart.yaml ] || continue
    PROJECT=${CHART#charts/}
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo ========= deploy: $CHART
    helm template $CHART --include-crds|kubectl apply -f - --server-side --force-conflicts
    echo
done


for T in capi capz; do
    PROJECT="cluster-api"
    case "$T" in
      capa)
        PROJECT="$PROJECT-provider-aws"
        ;;
      capz)
        PROJECT="$PROJECT-provider-azure"
        ;;
    esac
    [ -z "$PROJECT_ONLY" -o "$PROJECT_ONLY" == "$PROJECT" ] || continue
    echo "Waiting for ${T} controller:"
    kubectl events -n ${T}-system --watch &
    CH_PID=$!
    kubectl -n ${T}-system wait deployment/${T}-controller-manager --for condition=Available=True  --timeout=10m
    kill $CH_PID
    echo
done


