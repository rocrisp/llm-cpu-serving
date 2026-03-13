# Helm Template Changes Summary

## Files Modified

### 1. `helm/templates/workbench.yaml`
**Key Changes:**
- **Added annotation**: `notebooks.opendatahub.io/inject-auth: 'true'`
- **Image references updated** to use internal ImageStream:
  - Annotation: `notebooks.opendatahub.io/last-image-selection: 'redhat-ods-applications/custom-anythingllm:{{ .Values.images.anythingllm.tag }}'`
  - Container image: `image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/custom-anythingllm:{{ .Values.images.anythingllm.tag }}`
  - JUPYTER_IMAGE env: Same as container image
- **Removed OAuth proxy container** - Now auto-injected by OpenShift AI controller as `kube-rbac-proxy`
- **Removed volumes**:
  - `oauth-config` - Not needed with kube-rbac-proxy
  - `tls-certificates` - Not needed with kube-rbac-proxy
- **Kept containers**:
  - `anythingllm` - Main application container
  - `anythingllm-automation` - SQLite sidecar for API key setup

### 2. `helm/values.yaml`
**No changes** - Kept as-is:
```yaml
images:
  anythingllm:
    repository: "quay.io/rh-aiservices-bu/anythingllm-workbench"
    tag: "1.9.1"
```

## Files Removed

1. ✅ `helm/templates/anythingllm-oauth-secret.yaml` - Not needed, controller manages OAuth
2. ✅ `helm/templates/anythingllm-tls-service.yaml` - Not needed, controller creates services
3. ✅ `helm/templates/anythingllm-imagestream.yaml` - ImageStream exists in `redhat-ods-applications` namespace (managed by OpenShift AI)

## Resources Auto-Created by OpenShift AI Controller

The following resources are **automatically created** by the OpenShift AI Notebook controller and should NOT be in helm templates:

### Services (auto-created with ownerReferences)
- `anythingllm` - Main service on port 80 → targetPort 8888
- `anythingllm-kube-rbac-proxy` - Auth proxy service on port 8443 → targetPort 8443

### HTTPRoute (auto-created in redhat-ods-applications namespace)
- `nb-hr-assistant-anythingllm` - Routes traffic from gateway to backend
  - Backend: `anythingllm-kube-rbac-proxy:8443`
  - Path: `/notebook/hr-assistant/anythingllm`

### ReferenceGrant (auto-created)
- `notebook-httproute-access` - Allows cross-namespace HTTPRoute → Service references

### ConfigMap (auto-created)
- `anythingllm-kube-rbac-proxy-config` - Configuration for kube-rbac-proxy

### Secret (auto-created)
- `anythingllm-kube-rbac-proxy-tls` - TLS certificates for kube-rbac-proxy

## How It Works

1. Helm deploys Notebook resource with annotations:
   - `notebooks.opendatahub.io/inject-oauth: 'true'`
   - `notebooks.opendatahub.io/inject-auth: 'true'`

2. OpenShift AI Notebook controller sees these annotations and:
   - Injects `kube-rbac-proxy` sidecar container
   - Creates services with ownerReferences
   - Creates HTTPRoute in `redhat-ods-applications` namespace
   - Creates ReferenceGrant for cross-namespace access
   - Creates TLS certificates and ConfigMaps

3. Users access via Data Science Gateway:
   - URL: `https://data-science-gateway.apps.cluster-kj6qm.dynamic.redhatworkshops.io/notebook/hr-assistant/anythingllm`
   - OAuth login required
   - Proxied through kube-rbac-proxy to AnythingLLM workbench

## Manual Patches NOT Needed in Helm

The following `oc patch` commands were used during troubleshooting but are NOT needed in helm templates because resources are auto-managed:

- ❌ HTTPRoute patches - Controller reconciles these
- ❌ Service patches - Services have ownerReferences and are controlled by Notebook
- ✅ Notebook annotation patches - **Already added to workbench.yaml template**

## Verification

After deployment, verify:
```bash
# Check annotations
oc get notebook anythingllm -n hr-assistant -o jsonpath='{.metadata.annotations}' | jq .

# Check auto-created services
oc get svc -n hr-assistant

# Check HTTPRoute
oc get httproute -n redhat-ods-applications

# Check pod containers
oc get pod anythingllm-0 -n hr-assistant -o jsonpath='{.spec.containers[*].name}'
# Should show: anythingllm anythingllm-automation kube-rbac-proxy
```

## External Dependencies

### ImageStream (pre-existing in redhat-ods-applications)
- Name: `custom-anythingllm`
- Tag: `1.9.1`
- Source: `quay.io/rh-aiservices-bu/anythingllm-workbench:1.9.1`

This ImageStream must exist in the `redhat-ods-applications` namespace before deploying the helm chart.
