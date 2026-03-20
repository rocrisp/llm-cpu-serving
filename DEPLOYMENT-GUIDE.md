# Deployment Guide - Ensuring Portability Across Clusters

## Overview

This guide ensures the HR Assistant deployment will work reliably when moving to a new OpenShift cluster.

## Critical External Dependency

### ⚠️ AnythingLLM ImageStream (MUST EXIST)

**The deployment WILL FAIL if this ImageStream doesn't exist.**

The ImageStream must exist in the `redhat-ods-applications` namespace before deploying:

```bash
oc get imagestream custom-anythingllm -n redhat-ods-applications
```

### Why This Dependency Exists

1. The Notebook workbench references: `redhat-ods-applications/custom-anythingllm:1.9.1`
2. OpenShift AI expects notebook images to be ImageStreams (not direct container images)
3. The ImageStream provides:
   - Image caching in the internal registry
   - Version tracking and updates
   - Integration with OpenShift AI dashboard

### Creating the ImageStream on a New Cluster

Run this **once per cluster** before deploying:

```bash
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
```

**Note:** This must be created in `redhat-ods-applications` namespace (not in your project namespace).

## Pre-Deployment Checklist

Before deploying to any cluster, run:

```bash
./scripts/verify-prerequisites.sh
```

This will check:
- ✅ OpenShift connectivity
- ✅ OpenShift AI operator running
- ✅ Data Science Gateway configured
- ✅ **AnythingLLM ImageStream exists** (critical!)
- ✅ Storage classes available
- ✅ KServe/Serverless components
- ⚠️ Service Mesh or Gateway API

## What Gets Auto-Created by OpenShift AI

The following resources are **automatically created** by the OpenShift AI Notebook controller and are NOT in the Helm chart:

### Services (with ownerReferences to Notebook)
- `anythingllm` - Main service (port 80 → 8888)
- `anythingllm-kube-rbac-proxy` - Auth proxy (port 8443)

### HTTPRoute (in redhat-ods-applications namespace)
- `nb-hr-assistant-anythingllm`
  - Routes traffic from Data Science Gateway
  - Backend: `anythingllm-kube-rbac-proxy:8443`

### ReferenceGrant
- `notebook-httproute-access`
  - Allows cross-namespace access from HTTPRoute to Services

### ConfigMaps & Secrets
- `anythingllm-kube-rbac-proxy-config`
- `anythingllm-kube-rbac-proxy-tls`

### Container Injection
- `kube-rbac-proxy` sidecar container
  - Auto-injected when `notebooks.opendatahub.io/inject-auth: 'true'`
  - Provides RBAC-based authentication

## Cluster-Specific Configuration

### Storage Class

Update `helm/values.yaml` to match your cluster's storage:

```yaml
storageClassName: <your-storage-class>
```

Common options:
- **OpenShift Container Storage:** `ocs-external-storagecluster-ceph-rbd`
- **AWS EBS:** `gp3-csi`, `gp2`
- **Azure Disk:** `managed-premium`
- **GCP Persistent Disk:** `standard-rwo`

Check available storage classes:
```bash
oc get storageclass
```

## Deployment Workflow (New Cluster)

1. **Verify prerequisites:**
   ```bash
   ./scripts/verify-prerequisites.sh
   ```

2. **Create ImageStream** (if it doesn't exist):
   ```bash
   # See "Creating the ImageStream" section above
   ```

3. **Update storage class** in `helm/values.yaml` if needed

4. **Deploy:**
   ```bash
   PROJECT="hr-assistant"
   oc new-project ${PROJECT}
   helm install ${PROJECT} helm/ --namespace ${PROJECT}
   ```

5. **Verify deployment:**
   ```bash
   oc get pods -n ${PROJECT}
   # Expected: 3/3 Running for anythingllm-0
   ```

6. **Test access:**
   ```bash
   echo "https://$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}')/notebook/${PROJECT}/anythingllm/"
   ```

## What's in Helm vs Auto-Created

### Helm-Managed (in helm/templates/)
- ✅ Notebook resource (workbench.yaml)
- ✅ InferenceService (inferenceservice.yaml)
- ✅ ServingRuntime (servingruntime.yaml)
- ✅ Secrets for configuration (anythingllm-secret.yaml, anythingllm-api.yaml)
- ✅ ConfigMaps (vllm-chat-template-configmap.yaml)
- ✅ ServiceAccount (anythingllm-serviceaccount.yaml)
- ✅ PVC (workbench-pvc.yaml)
- ✅ Seed Job (init_job.yaml)
- ✅ Cosign verification Job (cosign-verify-job.yaml, when `signing.enabled`)
- ✅ Cosign public key Secret (cosign-pubkey-secret.yaml, when `signing.enabled`)

### Auto-Created by Controllers
- ❌ Services (owned by Notebook controller)
- ❌ HTTPRoute (created by Notebook controller)
- ❌ ReferenceGrant (created by Notebook controller)
- ❌ kube-rbac-proxy sidecar (injected by controller)
- ❌ TLS certificates and configs for auth proxy

## Troubleshooting Cross-Cluster Issues

### ImageStream Not Found
**Symptom:** Dashboard shows "Notebook image deleted"

**Fix:**
```bash
# Create the ImageStream (see above)
# Then delete the Notebook to pick it up:
oc delete notebook anythingllm -n hr-assistant
```

### Wrong Storage Class
**Symptom:** PVC stuck in "Pending" state

**Fix:**
```bash
# Update helm/values.yaml, then upgrade:
helm upgrade hr-assistant helm/ -n hr-assistant
```

### Gateway Not Found
**Symptom:** "no healthy upstream" error

**Fix:** Verify OpenShift AI and Data Science Gateway are installed:
```bash
oc get gateway data-science-gateway -n openshift-ingress
```

## Key Differences from Manual Deployment

This Helm deployment differs from manual workbench creation:

1. **Authentication:** Uses annotations to trigger auto-injection
   - `notebooks.opendatahub.io/inject-oauth: 'true'`
   - `notebooks.opendatahub.io/inject-auth: 'true'`

2. **No manual OAuth/TLS setup:** Controller handles it

3. **ImageStream reference:** Must use internal registry path

4. **Declarative:** Entire stack defined in Helm templates

## Maintenance

### Updating the Model

To switch models, update `helm/values.yaml`:
```yaml
model:
  storageUri: "hf://facebook/opt-350m"
  name: "opt-350m"
  maxModelLen: 2048
```

Then upgrade:
```bash
helm upgrade hr-assistant helm/ -n hr-assistant
```

### Updating AnythingLLM Version

1. Update ImageStream tag in `redhat-ods-applications` namespace
2. Update `helm/values.yaml`:
   ```yaml
   images:
     anythingllm:
       tag: "1.9.2"  # new version
   ```
3. Upgrade deployment

## Model Signing with Cosign (Optional)

When `signing.enabled: true` in `helm/values.yaml`, the chart runs a
[Sigstore cosign](https://github.com/sigstore/cosign) verification Job as a Helm
pre-install hook. The model must be stored as a signed OCI artifact instead of
loaded directly from HuggingFace.

### Prerequisites

- [cosign v3+](https://github.com/sigstore/cosign#installation)
- [oras](https://oras.land) (for pushing model files to OCI registries)
- Write access to an OCI registry (e.g., quay.io)

### Workflow

1. **Push model to OCI registry:**
   ```bash
   ./scripts/sign-model.sh push ./model-files quay.io/your-org/qwen25-05b:v1
   ```

2. **Sign the artifact:**
   ```bash
   ./scripts/sign-model.sh sign quay.io/your-org/qwen25-05b:v1
   ```

3. **Encode public key and update values.yaml:**
   ```bash
   ./scripts/sign-model.sh encode-pubkey
   ```
   Then set in `helm/values.yaml`:
   ```yaml
   model:
     storageUri: "oci://quay.io/your-org/qwen25-05b:v1"

   signing:
     enabled: true
     publicKey: "<base64-encoded cosign.pub>"
   ```

4. **Deploy as normal** — the verification Job runs automatically before resources
   are created. If the signature is invalid, Helm aborts the install.

### Key-Based vs Keyless

- **Key-based:** Generate a keypair with `./scripts/sign-model.sh generate-keys`.
  Store `cosign.pub` in `signing.publicKey`. Best for air-gapped environments.
- **Keyless (OIDC):** Leave `publicKey` empty, set `certificateIdentity` and
  `certificateOidcIssuer`. Best for CI/CD pipelines with OIDC providers
  (GitHub, Google, Microsoft).

### Troubleshooting

If `helm install` fails with a cosign verification error:

```bash
oc logs -n ${PROJECT} job/cosign-verify-model
```

Common causes:
- Model artifact was not signed
- Wrong public key in `signing.publicKey`
- Registry authentication not configured in the cluster
- `model.storageUri` still uses `hf://` instead of `oci://`

## Summary

**Most Important for Portability:**
1. ✅ Create `custom-anythingllm` ImageStream in `redhat-ods-applications`
2. ✅ Verify storage class matches your cluster
3. ✅ Ensure OpenShift AI and prerequisites are installed
4. ✅ Run `./scripts/verify-prerequisites.sh` before deploying

**The deployment is portable EXCEPT for the ImageStream dependency.**

Once the ImageStream exists, the Helm chart will deploy successfully on any compatible OpenShift AI cluster.
