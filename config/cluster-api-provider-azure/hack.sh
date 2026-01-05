#!/bin/bash -e
SCRIPT_DIR=$(dirname "$0")
ASO_WORKSPACE="stolostron"
ASO_VERSION="v2.13.0-hcpclusters.1"
ASO_CRDS="networksecuritygroups.network.azure.com vaults.keyvault.azure.com"

ASO_CRDS_CHECK=""
for i in $ASO_CRDS ; do 
   [ -n "$ASO_CRDS_CHECK" ] && ASO_CRDS_CHECK="$ASO_CRDS_CHECK or "
   ASO_CRDS_CHECK="$ASO_CRDS_CHECK.metadata.name == \"$i\""
done


ASO_DST_DIR="$PWD/config/base/aso-crds"
ASO_DST_K="$ASO_DST_DIR/kustomization.yaml"

echo creating: "$ASO_DST_DIR/aso-crds.yaml"
set -x
curl -fSsL "https://github.com/${ASO_WORKSPACE}/azure-service-operator/releases/download/${ASO_VERSION}/azureserviceoperator_customresourcedefinitions_${ASO_VERSION}.yaml" | \
	$YQ e ". | select(${ASO_CRDS_CHECK})" - | \
	sed 's/\$\$/$$$$/g' | \
	sed 's/namespace: azureserviceoperator-system/namespace: capz-system/g' \
	> "$ASO_DST_DIR/aso-crds.yaml"
echo "  - aso-crds.yaml" >> "$ASO_DST_K"

