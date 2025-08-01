#!/bin/bash
OUT_FILE=$(dirname $0)/aro-template-new.yaml


cat <<EOF | cat > $OUT_FILE
# Equivalent to:
# az group create --name "\${RESOURCEGROUPNAME}" --location "\${REGION}"
# This YAML creates a Resource Group named "\${RESOURCEGROUPNAME}" in the specified Azure region "\${REGION}".
apiVersion: resources.azure.com/v1api20200601
kind: ResourceGroup
metadata:
  name: \${RESOURCEGROUPNAME}
  namespace: default
spec:
  location: \${REGION}
---
# Equivalent to:
# az network vnet create -n "\${VNET}" -g "\${RESOURCEGROUPNAME}"
# This YAML creates a virtual network named "\${VNET}" in the "\${RESOURCEGROUPNAME}" resource group.
apiVersion: network.azure.com/v1api20201101
kind: VirtualNetwork
metadata:
  name: \${VNET}
  namespace: default
spec:
  location: \${REGION}
  owner:
    name: \${RESOURCEGROUPNAME}
  addressSpace:
    addressPrefixes:
      - 10.100.0.0/15
---
# Equivalent to:
# az network nsg create -n "\${NSG}" -g "\${RESOURCEGROUPNAME}"
# This YAML creates a Network Security Group (NSG) named "\${NSG}" in the "\${RESOURCEGROUPNAME}" resource group.
apiVersion: network.azure.com/v1api20201101
kind: NetworkSecurityGroup
metadata:
  name: \${NSG}
  namespace: default
spec:
  location: \${REGION}
  owner:
    name: \${RESOURCEGROUPNAME}
---
# Equivalent to:
# az network vnet subnet create -n "\${SUBNET}" -g "\${RESOURCEGROUPNAME}" --vnet-name "\${VNET}" --network-security-group "\${NSG}"
# This YAML creates a subnet named "\${SUBNET}" in the "\${VNET}" virtual network and associates it with the "\${NSG}" Network Security Group.
apiVersion: network.azure.com/v1api20201101
kind: VirtualNetworksSubnet
metadata:
  name: \${VNET}-\${SUBNET}
  namespace: default
spec:
  owner:
    name: \${VNET}
  addressPrefix: 10.100.76.0/24
  azureName: \${SUBNET}
  networkSecurityGroup:
    reference:
      name: \${NSG}
      group: network.azure.com
      kind: NetworkSecurityGroup
EOF

for IDENTITY_NAME in \
    \${USER}-\${CS_CLUSTER_NAME}-cp-control-plane-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-cluster-api-azure-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-cloud-controller-manager-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-ingress-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-disk-csi-driver-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-file-csi-driver-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-image-registry-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-cloud-network-config-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-cp-kms-\${OPERATORS_UAMIS_SUFFIX} \
    \
    \${USER}-\${CS_CLUSTER_NAME}-dp-disk-csi-driver-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-dp-image-registry-\${OPERATORS_UAMIS_SUFFIX} \
    \${USER}-\${CS_CLUSTER_NAME}-dp-file-csi-driver-\${OPERATORS_UAMIS_SUFFIX} \
    \
    \${USER}-\${CS_CLUSTER_NAME}-service-managed-identity-\${OPERATORS_UAMIS_SUFFIX} \
; do
cat >> $OUT_FILE <<EOF
---
# Equivalent to:
# az identity create -n "$IDENTITY_NAME" -g "\${RESOURCEGROUPNAME}"
# This YAML creates a managed identity named "$IDENTITY_NAME" in the "\${RESOURCEGROUPNAME}" resource group.
apiVersion: managedidentity.azure.com/v1api20230131
kind: UserAssignedIdentity
metadata:
  name: $IDENTITY_NAME
  namespace: default
spec:
  location: \${REGION}
  owner:
    name: \${RESOURCEGROUPNAME}
  operatorSpec:
    configMaps:
      principalId:
        name: identity-map-$IDENTITY_NAME
        key: principalId
      clientId:
        name: identity-map-$IDENTITY_NAME
        key: clientId
EOF
done

cat >> $OUT_FILE <<EOF
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: AROControlPlane
metadata:
 name: \${CS_CLUSTER_NAME}-control-plane
 namespace: default
spec:
 aroClusterName: \${CS_CLUSTER_NAME}
 platform:
   location: \${REGION}
   resourceGroup: \${RESOURCEGROUPNAME}
   subnet: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourceGroups/\${RESOURCEGROUPNAME}/providers/Microsoft.Network/virtualNetworks/\${VNET}/subnets/\${SUBNET}"
   outboundType: LoadBalancer
   networkSecurityGroupId: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourceGroups/\${RESOURCEGROUPNAME}/providers/Microsoft.Network/networkSecurityGroups/\${NSG}"
   managedIdentities:
     controlPlaneOperators:
       cloudControllerManager: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-cloud-controller-manager-\${OPERATORS_UAMIS_SUFFIX}"
       cloudNetworkConfigManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-cloud-network-config-\${OPERATORS_UAMIS_SUFFIX}"
       clusterApiAzureManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-cluster-api-azure-\${OPERATORS_UAMIS_SUFFIX}"
       controlPlaneOperatorsManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-control-plane-\${OPERATORS_UAMIS_SUFFIX}"
       diskCsiDriverManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-disk-csi-driver-\${OPERATORS_UAMIS_SUFFIX}"
       fileCsiDriverManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-file-csi-driver-\${OPERATORS_UAMIS_SUFFIX}"
       imageRegistryManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-image-registry-\${OPERATORS_UAMIS_SUFFIX}"
       ingressManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-ingress-\${OPERATORS_UAMIS_SUFFIX}"
       kmsManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-cp-kms-\${OPERATORS_UAMIS_SUFFIX}"
     dataPlaneOperators:
       diskCsiDriverManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-dp-disk-csi-driver-\${OPERATORS_UAMIS_SUFFIX}"
       fileCsiDriverManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-dp-file-csi-driver-\${OPERATORS_UAMIS_SUFFIX}"
       imageRegistryManagedIdentities: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-dp-image-registry-\${OPERATORS_UAMIS_SUFFIX}"
     serviceManagedIdentity: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourcegroups/\${RESOURCEGROUPNAME}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/\${USER}-\${CS_CLUSTER_NAME}-service-managed-identity-\${OPERATORS_UAMIS_SUFFIX}"
 visibility: Public
 network:
   machineCIDR: "10.0.0.0/16"
   podCIDR: "10.128.0.0/14"
   serviceCIDR: "172.30.0.0/16"
   hostPrefix: 23
   networkType: OVNKubernetes
 domainPrefix: \${CS_CLUSTER_NAME}
 version: "\${OCP_VERSION}"
 channelGroup: stable
 versionGate: WaitForAcknowledge
 identityRef:
    kind: AzureClusterIdentity
    name: \${AZURE_CLUSTER_IDENTITY_NAME}
    namespace: \${AZURE_CLUSTER_IDENTITY_NAMESPACE}
 additionalTags:
   environment: production
   owner: sre-team
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AROMachinePool
metadata:
 name: \${CS_CLUSTER_NAME}-mp-0
 namespace: default
spec:
  nodePoolName: w-\${REGION}-mp-0
  version: "\${OCP_VERSION}"
  platform:
    subnet: "/subscriptions/\${AZURE_SUBSCRIPTION_ID}/resourceGroups/\${RESOURCEGROUPNAME}/providers/Microsoft.Network/virtualNetworks/\${VNET}/subnets/\${SUBNET}"
    vmSize: "Standard_D4s_v3"
    diskSizeGiB: 128
    diskStorageAccountType: "Premium_LRS"
labels:
   region: \${REGION}
taints:
  - key: "example.com/special"
    value: "true"
    effect: "NoSchedule"
additionalTags:
  environment: production
  cost-center: engineering
autoRepair: true
autoscaling:
  minReplicas: 2
  maxReplicas: 4
---
apiVersion: cluster.x-k8s.io/v1beta2
kind: MachinePool
metadata:
  name: \${CS_CLUSTER_NAME}-mp-0
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: \${CS_CLUSTER_NAME}
spec:
  replicas: 2
  clusterName: \${CS_CLUSTER_NAME}
  template:
    spec:
      bootstrap:
        dataSecretName: \${CS_CLUSTER_NAME}-kubeconfig
#        configRef:
#           apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
#           kind: KubeadmConfig
#           name: \${CS_CLUSTER_NAME}-mp-0
#           namespace: default
      clusterName: \${CS_CLUSTER_NAME}
      infrastructureRef:
        apiGroup: infrastructure.cluster.x-k8s.io
        kind: AROMachinePool
        name: \${CS_CLUSTER_NAME}-mp-0
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AROCluster
metadata:
 name: \${CS_CLUSTER_NAME}
 namespace: default
 labels:
   cluster.x-k8s.io/cluster-name: \${CS_CLUSTER_NAME}
spec:
---
apiVersion: cluster.x-k8s.io/v1beta2
kind: Cluster
metadata:
  name: \${CS_CLUSTER_NAME}
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
  controlPlaneRef:
    apiGroup: controlplane.cluster.x-k8s.io
    kind: AROControlPlane
    name: \${CS_CLUSTER_NAME}-control-plane
  infrastructureRef:
    apiGroup: infrastructure.cluster.x-k8s.io
    kind: AROCluster
    name: \${CS_CLUSTER_NAME}
---
EOF
