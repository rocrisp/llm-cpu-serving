#!/bin/bash
# Script to verify all prerequisites for deploying the HR Assistant

set -e

echo "======================================"
echo "  HR Assistant Prerequisites Check"
echo "======================================"
echo ""

FAILURES=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
    FAILURES=$((FAILURES + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check 1: OpenShift cluster connectivity
echo "Checking OpenShift cluster connectivity..."
if oc whoami &>/dev/null; then
    print_success "Connected to OpenShift cluster"
    echo "  User: $(oc whoami)"
    echo "  Server: $(oc whoami --show-server)"
else
    print_failure "Not connected to OpenShift cluster"
    echo "  Run 'oc login' to connect to your cluster"
fi
echo ""

# Check 2: OpenShift AI operator
echo "Checking OpenShift AI operator..."
if oc get pods -n redhat-ods-operator -l name=rhods-operator &>/dev/null; then
    OPERATOR_PODS=$(oc get pods -n redhat-ods-operator -l name=rhods-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$OPERATOR_PODS" -gt 0 ]; then
        print_success "OpenShift AI operator is running ($OPERATOR_PODS pods)"
    else
        print_failure "OpenShift AI operator pods not found"
    fi
else
    print_failure "OpenShift AI operator namespace not found"
    echo "  Install OpenShift AI: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/"
fi
echo ""

# Check 3: Data Science Gateway
echo "Checking Data Science Gateway..."
if oc get gateway data-science-gateway -n openshift-ingress &>/dev/null; then
    GATEWAY_STATUS=$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
    if [ "$GATEWAY_STATUS" = "True" ]; then
        print_success "Data Science Gateway is running"
        GATEWAY_HOST=$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}' 2>/dev/null)
        echo "  Host: $GATEWAY_HOST"
    else
        print_failure "Data Science Gateway is not programmed"
    fi
else
    print_failure "Data Science Gateway not found"
    echo "  The gateway should be created automatically by OpenShift AI"
fi
echo ""

# Check 4: ImageStream
echo "Checking AnythingLLM ImageStream..."
if oc get imagestream custom-anythingllm -n redhat-ods-applications &>/dev/null; then
    IMAGE_TAG=$(oc get imagestream custom-anythingllm -n redhat-ods-applications -o jsonpath='{.spec.tags[0].name}' 2>/dev/null)
    print_success "ImageStream 'custom-anythingllm' exists (tag: $IMAGE_TAG)"
else
    print_warning "ImageStream 'custom-anythingllm' not found — creating it now..."
    cat <<EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: custom-anythingllm
  namespace: redhat-ods-applications
  labels:
    opendatahub.io/notebook-image: "true"
spec:
  lookupPolicy:
    local: true
  tags:
    - name: "1.9.1"
      from:
        kind: DockerImage
        name: quay.io/rh-aiservices-bu/anythingllm-workbench:1.9.1
      importPolicy:
        scheduled: true
      referencePolicy:
        type: Local
EOF
    if [ $? -eq 0 ]; then
        print_success "ImageStream 'custom-anythingllm' created successfully"
    else
        print_failure "Failed to create ImageStream 'custom-anythingllm'"
    fi
fi
echo ""

# Check 5: Storage Classes
echo "Checking storage classes..."
STORAGE_CLASSES=$(oc get storageclass --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$STORAGE_CLASSES" -gt 0 ]; then
    print_success "Found $STORAGE_CLASSES storage class(es)"
    echo "  Available storage classes:"
    oc get storageclass -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner --no-headers 2>/dev/null | sed 's/^/    • /'

    # Check for the default storage class in values.yaml
    DEFAULT_SC="ocs-external-storagecluster-ceph-rbd"
    if oc get storageclass "$DEFAULT_SC" &>/dev/null; then
        print_success "Default storage class '$DEFAULT_SC' exists"
    else
        print_warning "Default storage class '$DEFAULT_SC' not found"
        echo "  Update 'storageClassName' in helm/values.yaml to match your cluster"
    fi
else
    print_failure "No storage classes found"
fi
echo ""

# Check 6: KServe / Serverless
echo "Checking KServe and Serverless components..."
if oc get crd inferenceservices.serving.kserve.io &>/dev/null; then
    print_success "KServe CRDs are installed"
else
    print_failure "KServe CRDs not found"
    echo "  KServe requires OpenShift Serverless to be installed"
fi

if oc get ns knative-serving &>/dev/null; then
    print_success "Knative Serving is installed"
else
    print_failure "Knative Serving namespace not found"
    echo "  Install OpenShift Serverless: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.16/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-single-model-serving-platform_component-install"
fi
echo ""

# Check 7: Model Validation Operator (required for model signing verification)
echo "Checking Model Validation Operator..."
if oc get crd modelvalidations.ml.sigstore.dev &>/dev/null; then
    print_success "Model Validation Operator CRD installed"
    MVO_NS="openshift-operators"
    if oc get pods -n "$MVO_NS" -l control-plane=controller-manager --no-headers 2>/dev/null | grep -q model-validation; then
        MVO_RUNNING=$(oc get pods -n "$MVO_NS" --no-headers 2>/dev/null | grep model-validation-controller-manager | grep Running | wc -l | tr -d ' ')
        if [ "${MVO_RUNNING:-0}" -gt 0 ]; then
            print_success "Model Validation Operator is running in $MVO_NS ($MVO_RUNNING pod(s))"
        else
            print_warning "Model Validation Operator pod found in $MVO_NS but not Running"
        fi
    else
        print_warning "Model Validation Operator pod not found in $MVO_NS"
        echo "  Install from OperatorHub: Operators → OperatorHub → search 'Model Validation Operator'"
    fi
else
    print_failure "Model Validation Operator not installed (required for model signing)"
    echo "  Install from OperatorHub: Operators → OperatorHub → search 'Model Validation Operator'"
fi
echo ""

# Check 8: Service Mesh (optional - KServe can use OpenShift Ingress Gateway)
echo "Checking Service Mesh..."
if oc get ns istio-system &>/dev/null; then
    print_success "Istio (Service Mesh) namespace exists"
    if oc get pods -n istio-system -l app=istiod &>/dev/null; then
        ISTIOD_PODS=$(oc get pods -n istio-system -l app=istiod --no-headers 2>/dev/null | grep Running | wc -l | tr -d ' ')
        if [ "$ISTIOD_PODS" -gt 0 ]; then
            print_success "Istiod is running ($ISTIOD_PODS pods)"
        else
            print_warning "Istiod pods not running"
        fi
    fi
else
    # Check if using OpenShift Gateway instead
    if oc get gateway -A 2>/dev/null | grep -q "data-science-gateway"; then
        print_success "Using OpenShift Gateway (Service Mesh not required)"
    else
        print_warning "Service Mesh namespace not found (optional if using OpenShift Gateway)"
        echo "  For Service Mesh: https://docs.openshift.com/container-platform/latest/service_mesh/v2x/installing-ossm.html"
    fi
fi
echo ""

# Check 9: Resource availability (if namespace exists)
PROJECT="hr-assistant"
if oc get project "$PROJECT" &>/dev/null; then
    echo "Checking existing project '$PROJECT'..."
    print_warning "Project '$PROJECT' already exists"

    # Check if helm release exists
    if helm list -n "$PROJECT" | grep -q "$PROJECT"; then
        print_warning "Helm release '$PROJECT' already exists in namespace '$PROJECT'"
        echo "  Run 'helm uninstall $PROJECT -n $PROJECT' to remove it"
    fi
else
    print_success "Project '$PROJECT' does not exist (will be created)"
fi
echo ""

# Summary
echo "======================================"
echo "  Summary"
echo "======================================"
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All prerequisites are met! ✓${NC}"
    echo ""
    echo "You can now deploy with:"
    echo "  oc new-project hr-assistant"
    echo "  helm install hr-assistant helm/ --namespace hr-assistant"
    exit 0
else
    echo -e "${RED}$FAILURES prerequisite check(s) failed ✗${NC}"
    echo ""
    echo "Please resolve the issues above before deploying."
    exit 1
fi
