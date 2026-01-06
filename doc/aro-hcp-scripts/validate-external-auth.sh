#!/bin/bash
# validate-external-auth.sh
# Validates external authentication configuration for ARO HCP clusters

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Parse command line arguments
CLUSTER_NAME="${1}"
NAMESPACE="${2:-default}"

if [ -z "$CLUSTER_NAME" ]; then
    echo "Usage: $0 <cluster-name> [namespace]"
    echo "Example: $0 my-aro-cluster default"
    exit 1
fi

echo "=========================================="
echo "ARO HCP External Auth Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl not found. Please install kubectl."
    exit 1
fi
print_success "kubectl is available"

# Check if cluster exists
echo ""
echo "Checking AROControlPlane resource..."
if ! kubectl get arocontrolplane "${CLUSTER_NAME}-control-plane" -n "$NAMESPACE" &> /dev/null; then
    print_error "AROControlPlane '${CLUSTER_NAME}-control-plane' not found in namespace '$NAMESPACE'"
    exit 1
fi
print_success "AROControlPlane exists"

# Get the AROControlPlane spec
AROCP=$(kubectl get arocontrolplane "${CLUSTER_NAME}-control-plane" -n "$NAMESPACE" -o json)

# Check if external auth is enabled
echo ""
echo "Checking external authentication configuration..."
EXTERNAL_AUTH_ENABLED=$(echo "$AROCP" | jq -r '.spec.enableExternalAuthProviders // false')

if [ "$EXTERNAL_AUTH_ENABLED" != "true" ]; then
    print_warning "External authentication is not enabled"
    echo "  To enable, set spec.enableExternalAuthProviders: true"
    exit 0
fi
print_success "External authentication is enabled"

# Check if providers are configured
PROVIDER_COUNT=$(echo "$AROCP" | jq -r '.spec.externalAuthProviders | length // 0')

if [ "$PROVIDER_COUNT" -eq 0 ]; then
    print_error "No external auth providers configured"
    echo "  Add at least one provider to spec.externalAuthProviders"
    exit 1
fi
print_success "Found $PROVIDER_COUNT external auth provider(s)"

# Validate each provider
for i in $(seq 0 $((PROVIDER_COUNT - 1))); do
    echo ""
    echo "Validating provider $((i + 1))/$PROVIDER_COUNT..."

    PROVIDER=$(echo "$AROCP" | jq -r ".spec.externalAuthProviders[$i]")
    PROVIDER_NAME=$(echo "$PROVIDER" | jq -r '.name')

    echo "  Provider name: $PROVIDER_NAME"

    # Check issuer URL
    ISSUER_URL=$(echo "$PROVIDER" | jq -r '.issuer.issuerURL // empty')
    if [ -z "$ISSUER_URL" ]; then
        print_error "  Issuer URL is not set"
    elif [[ ! "$ISSUER_URL" =~ ^https:// ]]; then
        print_error "  Issuer URL must start with https://"
        echo "    Current value: $ISSUER_URL"
    else
        print_success "  Issuer URL: $ISSUER_URL"
    fi

    # Check audiences
    AUDIENCES=$(echo "$PROVIDER" | jq -r '.issuer.audiences // [] | length')
    if [ "$AUDIENCES" -eq 0 ]; then
        print_error "  No audiences configured"
    else
        print_success "  Configured $AUDIENCES audience(s)"
        echo "$PROVIDER" | jq -r '.issuer.audiences[]' | while read -r aud; do
            echo "    - $aud"
        done
    fi

    # Check for CA bundle
    CA_NAME=$(echo "$PROVIDER" | jq -r '.issuer.issuerCertificateAuthority.name // empty')
    if [ -n "$CA_NAME" ]; then
        if kubectl get configmap "$CA_NAME" -n "$NAMESPACE" &> /dev/null; then
            print_success "  CA ConfigMap '$CA_NAME' exists"

            # Check if ca-bundle.crt key exists
            if kubectl get configmap "$CA_NAME" -n "$NAMESPACE" -o jsonpath='{.data.ca-bundle\.crt}' &> /dev/null; then
                print_success "  CA bundle key 'ca-bundle.crt' exists"
            else
                print_error "  CA ConfigMap missing 'ca-bundle.crt' key"
            fi
        else
            print_error "  CA ConfigMap '$CA_NAME' not found"
        fi
    else
        print_info "  No custom CA configured (using system trust)"
    fi

    # Check OIDC clients
    CLIENT_COUNT=$(echo "$PROVIDER" | jq -r '.oidcClients // [] | length')
    if [ "$CLIENT_COUNT" -gt 0 ]; then
        echo "  OIDC Clients:"
        for j in $(seq 0 $((CLIENT_COUNT - 1))); do
            CLIENT=$(echo "$PROVIDER" | jq -r ".oidcClients[$j]")
            CLIENT_ID=$(echo "$CLIENT" | jq -r '.clientID')
            COMPONENT_NAME=$(echo "$CLIENT" | jq -r '.componentName')
            COMPONENT_NS=$(echo "$CLIENT" | jq -r '.componentNamespace')
            SECRET_NAME=$(echo "$CLIENT" | jq -r '.clientSecret.name')

            echo "    Client $((j + 1)): $COMPONENT_NAME (ns: $COMPONENT_NS)"
            echo "      Client ID: $CLIENT_ID"

            # Check if secret exists
            if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
                print_success "      Secret '$SECRET_NAME' exists"

                # Check if clientSecret key exists
                if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.clientSecret}' &> /dev/null; then
                    print_success "      Secret has 'clientSecret' key"
                else
                    print_error "      Secret missing 'clientSecret' key"
                fi
            else
                print_error "      Secret '$SECRET_NAME' not found"
                echo "        Create it with: kubectl create secret generic $SECRET_NAME --from-literal=clientSecret='<value>' -n $NAMESPACE"
            fi
        done
    else
        print_info "  No OIDC clients configured"
    fi

    # Check claim mappings
    USERNAME_CLAIM=$(echo "$PROVIDER" | jq -r '.claimMappings.username.claim // empty')
    GROUPS_CLAIM=$(echo "$PROVIDER" | jq -r '.claimMappings.groups.claim // empty')

    if [ -n "$USERNAME_CLAIM" ] || [ -n "$GROUPS_CLAIM" ]; then
        echo "  Claim Mappings:"
        if [ -n "$USERNAME_CLAIM" ]; then
            PREFIX_POLICY=$(echo "$PROVIDER" | jq -r '.claimMappings.username.prefixPolicy // "default"')
            print_success "    Username claim: $USERNAME_CLAIM (prefix: $PREFIX_POLICY)"
        fi
        if [ -n "$GROUPS_CLAIM" ]; then
            GROUPS_PREFIX=$(echo "$PROVIDER" | jq -r '.claimMappings.groups.prefix // ""')
            print_success "    Groups claim: $GROUPS_CLAIM (prefix: '$GROUPS_PREFIX')"
        fi
    else
        print_info "  No claim mappings configured (using defaults)"
    fi

    # Check validation rules
    RULE_COUNT=$(echo "$PROVIDER" | jq -r '.claimValidationRules // [] | length')
    if [ "$RULE_COUNT" -gt 0 ]; then
        echo "  Validation Rules: $RULE_COUNT configured"
        for k in $(seq 0 $((RULE_COUNT - 1))); do
            CLAIM=$(echo "$PROVIDER" | jq -r ".claimValidationRules[$k].requiredClaim.claim")
            VALUE=$(echo "$PROVIDER" | jq -r ".claimValidationRules[$k].requiredClaim.requiredValue")
            echo "    - $CLAIM must equal '$VALUE'"
        done
    else
        print_info "  No validation rules configured"
    fi
done

# Check for ASO HcpOpenShiftClustersExternalAuth resources
echo ""
echo "Checking ASO external auth resources..."
ASO_RESOURCES=$(kubectl get hcpopenshiftclustersexternalauth -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
ASO_COUNT=$(echo "$ASO_RESOURCES" | jq -r '.items | length')

if [ "$ASO_COUNT" -eq 0 ]; then
    print_warning "No HcpOpenShiftClustersExternalAuth resources found yet"
    echo "  These will be created by the controller during reconciliation"
else
    print_success "Found $ASO_COUNT HcpOpenShiftClustersExternalAuth resource(s)"

    # Check each ASO resource status
    for i in $(seq 0 $((ASO_COUNT - 1))); do
        ASO_NAME=$(echo "$ASO_RESOURCES" | jq -r ".items[$i].metadata.name")
        echo ""
        echo "  Resource: $ASO_NAME"

        # Check ready condition
        READY_STATUS=$(echo "$ASO_RESOURCES" | jq -r ".items[$i].status.conditions[] | select(.type==\"Ready\") | .status // \"Unknown\"")
        READY_REASON=$(echo "$ASO_RESOURCES" | jq -r ".items[$i].status.conditions[] | select(.type==\"Ready\") | .reason // \"Unknown\"")

        if [ "$READY_STATUS" == "True" ]; then
            print_success "    Status: Ready"
        elif [ "$READY_STATUS" == "False" ]; then
            print_error "    Status: Not Ready ($READY_REASON)"
        else
            print_warning "    Status: Unknown"
        fi

        # Check provisioning state
        PROV_STATE=$(echo "$ASO_RESOURCES" | jq -r ".items[$i].status.properties.provisioningState // \"Unknown\"")
        echo "    Provisioning State: $PROV_STATE"
    done
fi

echo ""
echo "=========================================="
echo "Validation Complete"
echo "=========================================="
