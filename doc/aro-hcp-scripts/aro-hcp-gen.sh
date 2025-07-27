#!/bin/bash
if [ -n "$1" ] ; then
    GEN_OUTPUT="$1"; shift
fi
# export OICD_RESOURCE_GROUP=mveber-oidc-issuer
# export USER_ASSIGNED_IDENTITY_ASO=mveber-aso-tests
# export USER_ASSIGNED_IDENTITY_ARO=mveber-aro-tests
# export CREATE_AZURE_CLUSTER_IDENTITY=true

TEMPLATE_FILE=$(dirname $0)/aro-template.yaml

# az cli
export AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export AZURE_SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
export USER=${USER:-user1}
export CS_CLUSTER_NAME=${CS_CLUSTER_NAME:-$USER-aro}
export NAME_PREFIX=${NAME_PREFIX:-aro-hcp}
export RESOURCEGROUPNAME="$USER-$CS_CLUSTER_NAME-$NAME_PREFIX-resgroup"

[ "$AZURE_SUBSCRIPTION_NAME" == "ARO SRE Team - INT (EA Subscription 3)"    ] && export REGION=${REGION:-uksouth}
[ "$AZURE_SUBSCRIPTION_NAME" == "ARO HCP - STAGE testing (EA Subscription)" ] && export REGION=${REGION:-uksouth}
export REGION=${REGION:-westus3}
if [ -n "$OICD_RESOURCE_GROUP" ] ; then
    export AZURE_ASO_TENANT_ID=$(az identity show --query tenantId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ASO}")
    export AZURE_ASO_CLIENT_ID=$(az identity show --query clientId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ASO}")
    export AZURE_ASO_PRINCIPAL_ID=$(az identity show --query principalId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ASO}")
    # az role assignment create --assignee  "${AZURE_ASO_PRINCIPAL_ID}" --role Contributor --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"
    export AZURE_TENANT_ID=$(az identity show --query tenantId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ARO}")
    export AZURE_CLIENT_ID=$(az identity show --query clientId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ARO}")
    export AZURE_PRINCIPAL_ID=$(az identity show --query principalId --output=tsv --resource-group="${OICD_RESOURCE_GROUP}" --name="${USER_ASSIGNED_IDENTITY_ARO}")
    # az role assignment create --assignee  "${AZURE_PRINCIPAL_ID}" --role Contributor --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"
else
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
    export CREATE_AZURE_CLUSTER_IDENTITY=true
fi
export OCP_VERSION=${OCP_VERSION:-openshift-v4.19.0}

OPERATORS_UAMIS_SUFFIX_FILE=operators-uamis-suffix.txt
if [ ! -f "$OPERATORS_UAMIS_SUFFIX_FILE" ] ; then
    openssl rand -hex 3 > "$OPERATORS_UAMIS_SUFFIX_FILE"
fi
export OPERATORS_UAMIS_SUFFIX=$(cat "$OPERATORS_UAMIS_SUFFIX_FILE")

export VNET="$NAME_PREFIX-vnet"
export SUBNET="$NAME_PREFIX-subnet"
export NSG="$NAME_PREFIX-nsg"


# Settings needed for AzureClusterIdentity used by the AzureCluster
export AZURE_CLUSTER_IDENTITY_NAME="cluster-identity"
export AZURE_CLUSTER_IDENTITY_NAMESPACE="default"
if [ -n "${AZURE_CLIENT_SECRET}" ] ; then
    export AZURE_CLUSTER_IDENTITY_SECRET_NAME="cluster-identity-secret"
    export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"
    oc create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}" --namespace "${AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE}"
fi


echo AZURE_TENANT_ID=${AZURE_TENANT_ID}
echo AZURE_CLIENT_ID=${AZURE_CLIENT_ID} AZURE_ASO_CLIENT_ID=${AZURE_ASO_CLIENT_ID} 
if [ -n "$CREATE_AZURE_CLUSTER_IDENTITY" ] ; then
(
cat <<EOF
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AzureClusterIdentity                                                                                                                                                                                                                   
metadata:
  name: ${AZURE_CLUSTER_IDENTITY_NAME}
  namespace: ${AZURE_CLUSTER_IDENTITY_NAMESPACE}
spec:
  allowedNamespaces: {}
  tenantID: "${AZURE_TENANT_ID}"
  clientID: "${AZURE_CLIENT_ID}"
EOF

if [ -z "${AZURE_CLIENT_SECRET}" ] ; then
#export AZURE_STORAGE_ACCOUNT="oidcissuer2320b428"                                        
#export AZURE_STORAGE_CONTAINER="oidc-test"
#
#export SERVICE_ACCOUNT_NAMESPACE=capz-system
#export SERVICE_ACCOUNT_NAME=capz-manager
#export SERVICE_ACCOUNT_ISSUER="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_STORAGE_CONTAINER}/"
#
#export AZURE_CLIENT_ID_USER_ASSIGNED_IDENTITY="$USER_ASSIGNED_IDENTITY"
#export AZURE_CONTROL_PLANE_MACHINE_TYPE=Standard_B2s
#export AZURE_LOCATION="$REGION"
#export AZURE_NODE_MACHINE_TYPE=Standard_B2s
#../../cluster-api/bin/clusterctl generate cluster azwi-quickstart --kubernetes-version v1.27.3  --worker-machine-count=3 > azwi-quickstart.yaml

cat <<EOF
  type: WorkloadIdentity # "ServicePrincipal", "UserAssignedMSI", "ManualServicePrincipal", "ServicePrincipalCertificate", "WorkloadIdentity", "UserAssignedIdentityCredential"
---
apiVersion: v1
kind: Secret
metadata:
 name: aso-credential
 namespace: default
stringData:
 AZURE_SUBSCRIPTION_ID: "${AZURE_SUBSCRIPTION_ID}"
 AZURE_TENANT_ID: "${AZURE_ASO_TENANT_ID}"
 AZURE_CLIENT_ID: "${AZURE_ASO_CLIENT_ID}"
EOF
else
cat <<EOF
  clientSecret:
    name: ${AZURE_CLUSTER_IDENTITY_SECRET_NAME}
    namespace: ${AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE}
  type: "ServicePrincipal" # "ServicePrincipal", "UserAssignedMSI", "ManualServicePrincipal", "ServicePrincipalCertificate", "WorkloadIdentity", "UserAssignedIdentityCredential"
---
apiVersion: v1
kind: Secret
metadata:
 name: aso-credential
 namespace: default
stringData:
 AZURE_SUBSCRIPTION_ID: "${AZURE_SUBSCRIPTION_ID}"
 AZURE_TENANT_ID: "${AZURE_TENANT_ID}"
 AZURE_CLIENT_ID: "${AZURE_CLIENT_ID}"
 AZURE_CLIENT_SECRET: "${AZURE_CLIENT_SECRET}"
EOF
fi
) | kubectl apply -f -
fi

if [ -n "$GEN_OUTPUT" ] ; then
    # missing in aro-clusteir: MANAGEDRGNAME="$USER-$CS_CLUSTER_NAME-managed-rg"
    envsubst  < $TEMPLATE_FILE > "$GEN_OUTPUT"
fi
