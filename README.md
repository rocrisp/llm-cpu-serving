# Serve a lightweight HR assistant

chat-example.png

Replace hours spent searching policy documents with higher-value relational work.

## Overview

The *Assistant to the HR Representative* is a lightweight quickstart designed to
give HR Representatives in Financial Services a trusted sounding board for discussions and decisions.

This quickstart was designed for environments where GPUs are not available or
necessary. By using vLLM on CPU-based infrastructure, this assistant can be
deployed to almost any OpenShift AI environment.

The Helm chart deploys:

- An OpenShift AI Project
- vLLM with CPU support running the model configured in [`helm/values.yaml`](helm/values.yaml)
- AnythingLLM, a chat interface connected to the vLLM inference service

> **Tip:** See [`helm/values.yaml`](helm/values.yaml) for all configurable settings including
> model selection, resource limits, and storage class.

For the detailed component architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Requirements

### Hardware

| | CPU | Memory | Storage | GPU |
|---|---|---|---|---|
| **Minimum** | 2 cores | 4 Gi | 5 Gi | None |
| **Recommended** | 8 cores | 8 Gi | 5 Gi | None |

### CPU Architecture Notes

Compiled for Intel CPUs. AVX512 BRGEMM optimizations are disabled by default for stability
(`VLLM_CPU_DISABLE_AVX512=1`).

Example AWS instance: [m6i.4xlarge](https://instances.vantage.sh/aws/ec2/m6i.4xlarge) (16 vCPU, 64 GiB)

### Software

- Red Hat OpenShift 4.16.24+
- Red Hat OpenShift AI 2.16.2+
- [Single-model server dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.16/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-single-model-serving-platform_component-install#configuring-automated-installation-of-kserve_component-install):
  - Red Hat OpenShift Service Mesh
  - Red Hat OpenShift Serverless
- [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
  (optional — required only when `signing.enabled: true`)

### Permissions

Standard user. No elevated cluster permissions required.

## Deploy

### Prerequisites

#### 1. OpenShift AI Installed and Configured

- Red Hat OpenShift AI 2.16.2+ with single-model serving platform:
  - Red Hat OpenShift Service Mesh
  - Red Hat OpenShift Serverless (KServe)

#### 2. Data Science Gateway

```bash
oc get gateway data-science-gateway -n openshift-ingress
```

Expected output should show the gateway in `PROGRAMMED` state.

#### 3. AnythingLLM ImageStream (REQUIRED)

```bash
oc get imagestream custom-anythingllm -n redhat-ods-applications
```

If missing, create it:

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

#### 4. Storage Class

Verify your cluster has a compatible storage class. Update `storageClassName` in
[`helm/values.yaml`](helm/values.yaml) if needed:

```bash
oc get storageclass
```

Common storage class names:

- OpenShift Container Storage: `ocs-external-storagecluster-ceph-rbd` (default)
- AWS EBS: `gp3-csi`, `gp2`
- Azure Disk: `managed-premium`
- GCP PD: `standard-rwo`

### Clone

```bash
git clone https://github.com/rocrisp/llm-cpu-serving.git && \
    cd llm-cpu-serving/
```

> This is a fork of [rh-ai-quickstart/llm-cpu-serving](https://github.com/rh-ai-quickstart/llm-cpu-serving).
> See [CHANGES.md](CHANGES.md) for modifications.

### Portability Checklist

Run the prerequisites check from the cloned repo:

```bash
./scripts/verify-prerequisites.sh
```

### Create the project

```bash
PROJECT="hr-assistant"

oc new-project ${PROJECT}
```

### Install with Helm

```bash
helm install ${PROJECT} helm/ --namespace ${PROJECT}
```

### Wait for pods

```bash
oc -n ${PROJECT} get pods -w
```

Wait until all pods show `Running` or `Completed`:

```
NAME                                            READY   STATUS      RESTARTS   AGE
anythingllm-0                                   3/3     Running     0          2m
anythingllm-seed-xxxxx                          0/1     Completed   0          2m
<model-name>-cpu-predictor-xxxxxxxxx-xxxxx      2/2     Running     0          2m
```

> The predictor pod may take 30-60 seconds to become ready as it downloads the model
> from HuggingFace on first start.

When `signing.enabled: true`, you will also see:

```
NAME                                            READY   STATUS      RESTARTS   AGE
model-download-xxxxx                            0/1     Completed   0          2m
<model-name>-cpu-predictor-xxxxxxxxx-xxxxx      2/2     Running     0          90s
```

The predictor pod will briefly show `Init:0/1` while the operator's model
validation init container verifies the signature, then transition to `Running`.

### Test

Get the OpenShift AI Dashboard URL:

```bash
oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}' && echo
```

Navigate to **Projects** → **hr-assistant** (or your `${PROJECT}` name).

![OpenShift AI Projects](docs/images/rhoai-1.png)

Open the **AnythingLLM** workbench.

![OpenShift AI Projects](docs/images/rhoai-2.png)

Click on the **Assistant to the HR Representative** workspace and start chatting.

#### Direct Access URL

```bash
echo "https://$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}')/notebook/${PROJECT}/anythingllm/"
```

#### Testing the API Directly

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

# Port-forward to the vLLM pod (keep running in one terminal)
POD=$(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o jsonpath='{.items[0].metadata.name}')
oc port-forward -n ${PROJECT} pod/${POD} 8080:8080

# In another terminal, test the chat completions endpoint
curl -X POST "http://localhost:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is HR compliance?\"}
    ],
    \"max_tokens\": 100
  }"
```

### Delete

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
```

## Switching Models

Update the `model` section in [`helm/values.yaml`](helm/values.yaml):

```yaml
model:
  storageUri: "hf://<org>/<model-name>"
  name: "<short-name>"
  maxModelLen: 2048
```

Then reinstall:

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
helm install ${PROJECT} helm/ --namespace ${PROJECT}
```

**Recommended CPU-friendly models:**

| Model | Parameters | Notes |
|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | Good balance of quality and speed |
| `HuggingFaceTB/SmolLM2-135M-Instruct` | 135M | Smallest, fastest |
| `HuggingFaceTB/SmolLM2-360M-Instruct` | 360M | Good balance |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | 1.7B | Best quality, more resources |
| `TinyLlama/TinyLlama-1.1B-Chat-v1.0` | 1.1B | Alternative option |

## Model Signing and Verification (Optional)

This chart supports cryptographic model verification using the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator)
and [Sigstore model-signing](https://github.com/sigstore/model-transparency). When
`signing.enabled: true`, the deployment flow becomes:

1. **model-download** (Helm pre-install hook) — copies a pre-signed model from an
   OCI image (or downloads a `.tar.gz` archive) onto a PVC
2. **ModelValidation CR** — tells the operator how to verify the model (public key
   or Sigstore keyless)
3. **Webhook injection** — the operator's mutating webhook intercepts the predictor
   pod (via the `validation.ml.sigstore.dev/ml` label) and injects a
   `model-validation` init container
4. **Init container verification** — the injected init container verifies the model
   signature before the main vLLM container starts. If verification fails, the pod
   stays in `Init:Error` and never serves traffic

The predictor pod then mounts the PVC and loads the verified model from
`/data/signed-model` instead of downloading from HuggingFace.

### Architecture

```
helm install
    |
    v
[PVC created] --> [model-download Job] --> model files + model.sig on PVC
                                                |
                                                v
                  [ModelValidation CR] <--- created by Helm
                  [InferenceService]   <--- label: validation.ml.sigstore.dev/ml
                                                |
                                                v
                  [Operator Webhook] -------> injects init container
                                                |
                                                v
                  [model-validation init] --> verifies signature
                                                |  (pass)
                                                v
                  [kserve-container]   -------> loads model from /data/signed-model
```

### Prerequisites

1. **Model Validation Operator** installed on the cluster:

```bash
# Install via OLM (OpenShift)
oc apply -k https://github.com/sigstore/model-validation-operator/config/overlays/olm

# Or for non-OLM clusters with cert-manager
kubectl apply -k https://github.com/sigstore/model-validation-operator/config/overlays/production
```

Verify the operator is running:

```bash
oc get pods -n model-validation-operator-system
oc get crd modelvalidations.ml.sigstore.dev
```

2. **model-signing** Python package (for signing models locally):

```bash
pip install model-signing
```

### Quick Start — Sign a Model

```bash
# 1. Download the model locally
huggingface-cli download Qwen/Qwen2.5-0.5B-Instruct --local-dir ./model-files

# 2. Generate a signing key pair
openssl ecparam -genkey -name prime256v1 -noout -out signing-key.pem
openssl ec -in signing-key.pem -pubout -out signing-key.pub

# 3. Sign the model with your private key
python3 -m model_signing sign key \
    --private_key signing-key.pem \
    --signature ./model-files/model.sig \
    --ignore-git-paths \
    ./model-files

# 4. Verify locally
python3 -m model_signing verify key \
    --public_key signing-key.pub \
    --signature ./model-files/model.sig \
    --ignore-git-paths \
    ./model-files

# 5. Package as an OCI image and push to a registry
cat > Containerfile <<EOF
FROM busybox:latest
COPY model-files/ /model/
EOF
podman build --platform linux/amd64 -t quay.io/yourorg/signed-model:v1 .
podman push quay.io/yourorg/signed-model:v1
```

> The helper script `./scripts/sign-model.sh` wraps the sign, verify, and archive
> steps. Run `./scripts/sign-model.sh` without arguments for usage.

### Enable in values.yaml

**Key-based verification** (recommended for air-gapped or private models):

```yaml
signing:
  enabled: true
  modelImage: "quay.io/yourorg/signed-model:v1"
  signaturePath: "model.sig"
  storageSize: "2Gi"
  ignoreGitPaths: true
  publicKeyData: |
    -----BEGIN PUBLIC KEY-----
    <paste contents of signing-key.pub>
    -----END PUBLIC KEY-----
```

**Sigstore keyless verification** (ties to an OIDC identity — no key management):

```yaml
signing:
  enabled: true
  modelImage: "quay.io/yourorg/signed-model:v1"
  signaturePath: "model.sig"
  storageSize: "2Gi"
  ignoreGitPaths: true
  certificateIdentity: "user@example.com"
  certificateOidcIssuer: "https://accounts.google.com"
```

### How It Works on Deploy

On `helm install`:

1. The **model-storage PVC** is created (pre-install hook, weight -10)
2. The **model-download Job** copies model files from the OCI image to the PVC
   (pre-install hook, weight -5)
3. Helm creates the **ModelValidation CR**, **signing-pubkey Secret** (if using
   key-based verification), **ServingRuntime**, and **InferenceService**
4. When the predictor pod is created, the operator's webhook detects the
   `validation.ml.sigstore.dev/ml` label and injects a `model-validation` init
   container that inherits all volume mounts from the main containers
5. The init container runs the verification agent — on success, the pod proceeds
   to start vLLM; on failure, the pod stays in `Init:Error`

### Helm Resources Created

| Resource | Purpose |
|---|---|
| `PersistentVolumeClaim/model-storage` | Stores the signed model (pre-install hook) |
| `Job/model-download` | Copies model from OCI image to PVC (pre-install hook) |
| `Secret/model-signing-pubkey` | Public key for verification (key-based only) |
| `ModelValidation/<name>-validation` | Tells operator how to verify the model |
| `InferenceService` | Predictor pod with `validation.ml.sigstore.dev/ml` label |
| `ServingRuntime` | vLLM runtime with PVC + key volume mounts |

### Testing Model Validation

After deploying with `signing.enabled: true`:

```bash
PROJECT="hr-assistant"

# 1. Check the model-download Job completed
oc logs -n ${PROJECT} job/model-download

# 2. Check the operator injected the init container
oc get pods -n ${PROJECT} -l serving.kserve.io/inferenceservice -o jsonpath='{.items[0].spec.initContainers[*].name}'
# Expected: model-validation

# 3. Check the init container verification succeeded
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation
# Expected: "Verification succeeded"

# 4. Check the operator logs
oc logs -n model-validation-operator-system deployment/model-validation-controller-manager --tail=20

# 5. Verify the model is loaded from the PVC (not HuggingFace)
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')
oc exec -n ${PROJECT} $(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o jsonpath='{.items[0].metadata.name}') \
    -c kserve-container -- curl -s http://localhost:8080/v1/models | python3 -m json.tool
# root should show "/data/signed-model"

# 6. Test inference
oc exec -n ${PROJECT} anythingllm-0 -c anythingllm -- \
    curl -s http://${MODEL_NAME}-cpu-predictor:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":30}"
```

### What Happens on Verification Failure

If the model signature is invalid or missing, the init container exits with an
error. The predictor pod will show `Init:Error` and never start serving:

```bash
# Check what went wrong
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation

# Common causes:
# - model.sig missing from the OCI image
# - Wrong public key (doesn't match the key used to sign)
# - Model files modified after signing
# - Wrong certificateIdentity/certificateOidcIssuer (keyless mode)
```

### Disabling Model Signing

Set `signing.enabled: false` in `values.yaml`. The chart reverts to downloading
the model directly from HuggingFace via `model.storageUri`.

## Vector DB Attestation and Integrity (Optional)

When `attestation.enabled: true`, the chart creates a baseline SHA-512 hash of the
LanceDB vector database after document seeding and periodically verifies it hasn't
been tampered with.

### Enable in values.yaml

```yaml
attestation:
  enabled: true
  schedule: "0 */6 * * *"    # check every 6 hours
  vectorDbPath: "/opt/app-root/src/anythingllm/storage/lancedb"
```

### How It Works

1. **Attestation** (post-install hook): After documents are seeded, a Job computes
   SHA-512 of all LanceDB files and stores the hash in a `vectordb-attestation` ConfigMap.
2. **Integrity CronJob**: Runs on schedule, re-computes the hash, and compares it
   against the baseline. Results (`PASS`/`FAIL`) are written to the ConfigMap.

### Check Integrity Status

```bash
oc get configmap vectordb-attestation -n ${PROJECT} -o yaml
```

Key fields: `baseline-hash`, `last-check`, `last-result` (`PASS`/`FAIL`/`ERROR`).

## Troubleshooting

### Workbench shows "Notebook image deleted"

The ImageStream `custom-anythingllm` is missing. See [Prerequisites](#3-anythingllm-imagestream-required).

### Workbench not accessible / "no healthy upstream"

```bash
oc get pod anythingllm-0 -n ${PROJECT}           # should show 3/3 Running
oc get svc -n ${PROJECT}                          # should show anythingllm services
```

### vLLM pod not starting

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

oc logs -n ${PROJECT} $(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o name) -c kserve-container
oc describe pod -n ${PROJECT} $(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o name)
```

### Port-forward or curl fails

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

oc get pods -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor
POD=$(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o jsonpath='{.items[0].metadata.name}')
oc port-forward -n ${PROJECT} pod/${POD} 8080:8080
```

### Vector DB integrity check fails

```bash
# Check CronJob logs
oc logs -n ${PROJECT} job/$(oc get jobs -n ${PROJECT} -l app=vectordb-integrity --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)

# View attestation state
oc get configmap vectordb-attestation -n ${PROJECT} -o jsonpath='{.data}' | python3 -m json.tool
```

If `last-result` is `FAIL`, the vector DB was modified after attestation. This could be
a legitimate document update or an integrity violation. Re-attest after any intentional
change by deleting and re-running the attestation Job.

### Model validation init container fails

```bash
# Check the init container logs
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation

# Check the model-download Job
oc logs -n ${PROJECT} job/model-download

# Check the ModelValidation CR
oc get modelvalidation -n ${PROJECT} -o yaml

# Check the operator webhook logs
oc logs -n model-validation-operator-system deployment/model-validation-controller-manager --tail=30

# Verify the operator is running
oc get pods -n model-validation-operator-system
```

Common causes: Model Validation Operator not installed, unsigned model, missing
`model.sig`, wrong public key, wrong certificate identity/issuer (keyless mode),
or model files modified after signing.

### Operator webhook not injecting init container

If the predictor pod starts without a `model-validation` init container:

```bash
# Verify the label is on the predictor pod
oc get pods -n ${PROJECT} -l serving.kserve.io/inferenceservice --show-labels | grep validation

# Verify the ModelValidation CR exists
oc get modelvalidation -n ${PROJECT}

# Check the namespace is not ignored
oc get namespace ${PROJECT} -o jsonpath='{.metadata.labels}' | grep -o 'validation.ml.sigstore.dev/ignore' && echo "IGNORED" || echo "OK"

# Check the webhook is registered
oc get mutatingwebhookconfiguration | grep validation
```

### Storage issues

```bash
oc get storageclass
oc get pvc -n ${PROJECT}
oc describe pvc anythingllm -n ${PROJECT}
```

Update `storageClassName` in [`helm/values.yaml`](helm/values.yaml) if needed.

## References

**Supply Chain Security:**

- Model Validation Operator: [sigstore/model-validation-operator](https://github.com/sigstore/model-validation-operator)
- Model signing: [sigstore/model-transparency](https://github.com/sigstore/model-transparency)
- Sigstore: [sigstore.dev](https://www.sigstore.dev)

**Runtime & Infrastructure:**

- Runtime: [vLLM CPU](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html)
- Runtime image: [quay.io/rh-aiservices-bu/vllm-cpu-openai-ubi9](https://quay.io/repository/rh-aiservices-bu/vllm-cpu-openai-ubi9)
- Runtime code: [github.com/rh-aiservices-bu/llm-on-openshift](https://github.com/rh-aiservices-bu/llm-on-openshift/tree/main/serving-runtimes/vllm_runtime)
- AnythingLLM: [Mintplex-Labs/anything-llm](https://github.com/Mintplex-Labs/anything-llm)

**Fork Information:**

- Original: [rh-ai-quickstart/llm-cpu-serving](https://github.com/rh-ai-quickstart/llm-cpu-serving)
- This fork: [rocrisp/llm-cpu-serving](https://github.com/rocrisp/llm-cpu-serving)
- Changelog: [CHANGES.md](CHANGES.md)

## Tags

- **Industry:** Adopt and scale AI
- **Product:** OpenShift AI
- **Use case:** Productivity
