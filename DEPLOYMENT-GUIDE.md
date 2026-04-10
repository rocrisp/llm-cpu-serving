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
- ✅ ModelValidation CR (model-validation-cr.yaml)
- ✅ Signing public key Secret (signing-pubkey-secret.yaml)
- ✅ Vector DB attestation Job (vectordb-attestation-job.yaml, when `attestation.enabled`)
- ✅ Vector DB integrity CronJob (vectordb-integrity-cronjob.yaml, when `attestation.enabled`)
- ✅ Attestation ConfigMap (vectordb-attestation-configmap.yaml, when `attestation.enabled`)
- ✅ Integrity RBAC (vectordb-attestation-rbac.yaml, when `attestation.enabled`)

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
  storageUri: "hf://Qwen/Qwen2.5-1.5B-Instruct"
  name: "qwen25-15b"
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

## Model Signing and Verification

The chart integrates with the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator)
to enforce cryptographic model verification before the predictor pod serves traffic.

### How It Works

1. **ModelValidation CR** — tells the operator how to verify the model
2. **Operator webhook** — intercepts the predictor pod (via the
   `validation.ml.sigstore.dev/ml` label) and injects a `model-validation`
   init container
3. **Init container** — verifies the signature; if it fails, the pod stays
   in `Init:Error` and never serves traffic

### Prerequisites

- [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
  installed on the cluster:
  ```bash
  oc apply -k https://github.com/sigstore/model-validation-operator/config/overlays/olm
  ```
- [model-signing](https://github.com/sigstore/model-transparency) Python package
  (for signing models locally): `pip install model-signing`

### Signing Workflow

For the full step-by-step guide, see **[docs/SIGNING-GUIDE.md](docs/SIGNING-GUIDE.md)**.

Quick reference:

```bash
# 1. Set up environment
python3 -m venv signing-env && source signing-env/bin/activate

# 2. Download the model
git lfs install
git clone https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct ./model-files
rm -rf ./model-files/.git ./model-files/.gitattributes

# 3. Sign the model (install model-transparency first)
git clone https://github.com/sigstore/model-transparency
cd model-transparency && pip3 install . && cd ..
python3 -m model_signing sign sigstore --signature ./model-files/model.sig ./model-files

# 4. Upload signed model to HuggingFace
pip3 install huggingface_hub
hf auth login
hf upload YOUR_HF_USERNAME/signed-model ./model-files .
```

### Configuration

```yaml
signing:
  enabled: true
  signaturePath: "model.sig"
  ignoreGitPaths: true
  publicKeyData: |
    -----BEGIN PUBLIC KEY-----
    <paste contents of signing-key.pub>
    -----END PUBLIC KEY-----
```

### Verification Methods

- **Key-based:** Set `publicKeyData` with the PEM-encoded public key.
  Best for air-gapped environments.
- **Keyless (OIDC):** Set `certificateIdentity` and `certificateOidcIssuer`.
  Best for CI/CD pipelines with OIDC providers (GitHub, Google).

### Troubleshooting

```bash
# Check the init container verification
oc logs -n hr-assistant -l serving.kserve.io/inferenceservice -c model-validation

# Check the storage initializer (model download)
oc logs -n hr-assistant -l serving.kserve.io/inferenceservice -c storage-initializer

# Check operator logs
oc logs -n model-validation-operator-system deployment/model-validation-controller-manager --tail=20
```

Common causes:
- Model Validation Operator not installed
- Model files not signed (missing `model.sig`)
- Wrong public key or certificate identity/issuer
- Model files modified after signing

## Vector DB Attestation and Integrity (Optional)

When `attestation.enabled: true` in `helm/values.yaml`, the chart provides tamper
detection for the LanceDB vector database used by AnythingLLM.

### How It Works

1. **Post-install attestation Job** (`vectordb-attest`):
   - Waits for `anythingllm-0` to be ready and documents to be seeded
   - Execs into the pod, computes SHA-512 of all LanceDB files
   - Stores the baseline hash and SLSA-style provenance in a ConfigMap

2. **Periodic integrity CronJob** (`vectordb-integrity-check`):
   - Runs on the configured schedule (default: every 6 hours)
   - Re-computes the hash and compares against the baseline
   - Writes `PASS` / `FAIL` / `ERROR` to the ConfigMap

### Configuration

```yaml
attestation:
  enabled: true
  schedule: "0 */6 * * *"
  vectorDbPath: "/opt/app-root/src/anythingllm/storage/lancedb"
```

### RBAC

The feature creates a dedicated `vectordb-integrity` ServiceAccount with minimal
permissions: pod get/list, pod/exec create (for `anythingllm-0` only), and
configmap patch (for `vectordb-attestation` only).

### Monitoring

```bash
# Check attestation status
oc get configmap vectordb-attestation -n hr-assistant -o yaml

# Check CronJob history
oc get jobs -n hr-assistant -l app=vectordb-integrity

# View latest integrity check logs
oc logs -n hr-assistant job/$(oc get jobs -n hr-assistant --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
```

### Re-Attestation

After intentionally updating documents, re-run the attestation to set a new baseline:

```bash
oc delete job vectordb-attest -n hr-assistant
oc create job vectordb-attest-manual --from=cronjob/vectordb-integrity-check -n hr-assistant
```

Or redeploy with Helm to trigger the post-install hook.

## Summary

**Most Important for Portability:**
1. ✅ Create `custom-anythingllm` ImageStream in `redhat-ods-applications`
2. ✅ Verify storage class matches your cluster
3. ✅ Ensure OpenShift AI and prerequisites are installed
4. ✅ Run `./scripts/verify-prerequisites.sh` before deploying

**The deployment is portable EXCEPT for the ImageStream dependency.**

Once the ImageStream exists, the Helm chart will deploy successfully on any compatible OpenShift AI cluster.
