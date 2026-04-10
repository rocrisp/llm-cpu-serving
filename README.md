# Serve a lightweight HR assistant

![chat-example.png](docs/images/chat-example.png)

Replace hours spent searching policy documents with higher-value relational work.

## Overview

The *Assistant to the HR Representative* is a lightweight quickstart designed to
give HR Representatives in Financial Services a trusted sounding board for discussions and decisions.

This quickstart was designed for environments where GPUs are not available or
necessary. By using vLLM on CPU-based infrastructure, this assistant can be
deployed to almost any OpenShift AI environment.

The Helm chart deploys:

- A **cryptographically signed and verified AI model** using the
  [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
  and [Sigstore](https://www.sigstore.dev) — the model's integrity is verified
  before it can serve traffic
- vLLM with CPU support running the verified model
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
  for cryptographic model verification at deployment time

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

#### 5. Model Validation Operator

Install the operator that enforces model signature verification:

```bash
oc apply -k https://github.com/sigstore/model-validation-operator/config/overlays/olm
```

Verify it's running:

```bash
oc get pods -n model-validation-operator-system
oc get crd modelvalidations.ml.sigstore.dev
```

#### 6. Model

The model must be signed and uploaded to HuggingFace before deployment.
Follow the [Signing Guide](docs/SIGNING-GUIDE.md) for the complete workflow.
The signed model is referenced at [install time](#install-with-helm) via `--set model.storageUri`.

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
helm install ${PROJECT} helm/ --namespace ${PROJECT} \
    --set signing.enabled=true \
    --set model.storageUri=hf://YOUR_HF_USERNAME/signed-model
```

Replace `YOUR_HF_USERNAME` with the HuggingFace username you used when
uploading the signed model in the [Signing Guide](docs/SIGNING-GUIDE.md).

Helm executes in this order:

1. **Main resources** — creates the `ModelValidation` CR, `ServingRuntime`,
   `InferenceService`, AnythingLLM workbench, and supporting resources
2. **Operator webhook** — the Model Validation Operator detects the predictor pod
   and injects a `model-validation` init container that verifies the signature

### Wait for pods

```bash
oc -n ${PROJECT} get pods -w
```

Watch the deployment progress:

```
NAME                                            READY   STATUS      RESTARTS   AGE
anythingllm-0                                   3/3     Running     0          2m
anythingllm-seed-xxxxx                          0/1     Completed   0          2m
<model-name>-cpu-predictor-xxxxxxxxx-xxxxx      0/3     Init:1/2    0          30s    <-- verifying signature
<model-name>-cpu-predictor-xxxxxxxxx-xxxxx      2/2     Running     0          90s    <-- verification passed
```

The `Init:1/2` phase is the Model Validation Operator's init container verifying
the cryptographic signature. Once it passes, the pod transitions to `Running`.
If verification fails, the pod stays in `Init:Error` and the model is never served.

### Test

#### Access the UI

Get the OpenShift AI Dashboard URL:

```bash
oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}' && echo
```

Navigate to **Projects** → **hr-assistant** (or your `${PROJECT}` name).

![OpenShift AI Projects](docs/images/rhoai-1.png)

Open the **AnythingLLM** workbench.

![OpenShift AI Projects](docs/images/rhoai-2.png)

Click on the **Assistant to the HR Representative** workspace and start chatting.

**Direct Access URL:**

```bash
echo "https://$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}')/notebook/${PROJECT}/anythingllm/"
```

#### Test the API directly

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

# Port-forward to the vLLM pod (keep running in one terminal)
POD=$(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o jsonpath='{.items[0].metadata.name}')
oc port-forward -n ${PROJECT} pod/${POD} 8080:8080

# In another terminal, test the chat completions endpoint
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"What is HR compliance?\"}
    ],
    \"max_tokens\": 100
  }" | python3 -m json.tool
```

Expected: a JSON response with `choices[0].message.content` containing the model's answer.

#### Validate model signing

Run these checks after deploying to confirm the model signing and verification
flow is working end-to-end:

```bash
PROJECT="hr-assistant"
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

# Step 1: Confirm that Kserve downloaded the model
echo "=== Step 3: Model downloaded ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c storage-initializer

# Step 2: Check verification succeeded
echo "=== Step 4: Verification result ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation
# Expected: "Verification succeeded"

# Step 3: Confirm model is loaded
echo "=== Step 5: Model source ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c kserve-container | head -5
# Expected: model path shows /data/signed-model

# Step 4: Test inference through the verified model
echo "=== Step 6: Inference test ==="
oc exec -n ${PROJECT} anythingllm-0 -c anythingllm -- \
    curl -s http://${MODEL_NAME}-cpu-predictor:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":30}"
# Expected: JSON response with choices[0].message.content
```

All steps passing confirms: the signed model was downloaded, the operator
injected the verification init container, the signature was verified, and the
model is serving traffic through the verified path.

> For a detailed validation report with full command output, see
> [VALIDATION-REPORT.md](VALIDATION-REPORT.md).

### Delete

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
```

## Switching Models

To use a different model, you must sign it, package it as an OCI image, and update
`values.yaml`:

1. **Sign and package the new model** (see [Sign a Model](#sign-a-model)):

```bash
hf download <org>/<model-name> --local-dir ./model-files
./scripts/sign-model.sh sign ./model-files --key signing-key.pem
podman build --platform linux/amd64 -t quay.io/yourorg/<model-name>-signed:v1 .
podman push quay.io/yourorg/<model-name>-signed:v1
```

2. **Update [`helm/values.yaml`](helm/values.yaml):**

```yaml
model:
  name: "<short-name>"
  maxModelLen: 2048

signing:
  modelImage: "quay.io/yourorg/<model-name>-signed:v1"
```

3. **Reinstall:**

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
helm install ${PROJECT} helm/ --namespace ${PROJECT}
```

**Recommended CPU-friendly models:**

| Model | Parameters | Notes |
|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | Good balance of quality and speed (default) |
| `HuggingFaceTB/SmolLM2-135M-Instruct` | 135M | Smallest, fastest |
| `HuggingFaceTB/SmolLM2-360M-Instruct` | 360M | Good balance |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | 1.7B | Best quality, more resources |
| `TinyLlama/TinyLlama-1.1B-Chat-v1.0` | 1.1B | Alternative option |

## Model Signing and Verification

All models deployed by this chart are cryptographically signed and verified
using the [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
and [Sigstore model-signing](https://github.com/sigstore/model-transparency).
The deployment flow is:

1. **ModelValidation CR** — tells the operator how to verify the model (public key
   or Sigstore keyless)
2. **Webhook injection** — the operator's mutating webhook intercepts the predictor
   pod (via the `validation.ml.sigstore.dev/ml` label) and injects a
   `model-validation` init container
3. **Init container verification** — the injected init container verifies the model
   signature before the main vLLM container starts. If verification fails, the pod
   stays in `Init:Error` and never serves traffic

### Architecture

```
helm install
    |
    v
[PVC created] --> [ModelValidation CR] <--- created by Helm
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

### Sign a Model

For the complete step-by-step guide — including virtual environment setup,
installing the HuggingFace CLI, downloading the model, signing, verifying,
and uploading to HuggingFace — see **[docs/SIGNING-GUIDE.md](docs/SIGNING-GUIDE.md)**.

Quick reference (key-based signing):

```bash
# 1. Set up environment
python3 -m venv signing-env && source signing-env/bin/activate
pip3 install huggingface_hub

# 2. Download the model
hf download Qwen/Qwen2.5-0.5B-Instruct --local-dir ./model-files
rm -rf ./model-files/.git ./model-files/.gitattributes

# 3. Install model signing
git clone https://github.com/sigstore/model-transparency
cd model-transparency && pip3 install . && cd ..

# 4. Generate keys and sign
openssl ecparam -genkey -name prime256v1 -noout -out signing-key.pem
openssl ec -in signing-key.pem -pubout -out signing-key.pub
python3 -m model_signing sign key --private_key signing-key.pem ./model-files

# 5. Verify locally
python3 -m model_signing verify key \
    --signature ./model-files/model.sig \
    --public_key signing-key.pub \
    ./model-files

# 6. Package as an OCI image and push to a registry
cat > Containerfile <<EOF
FROM busybox:latest
COPY model-files/ /model/
EOF
podman build --platform linux/amd64 -t quay.io/yourorg/signed-model:v1 .
podman push quay.io/yourorg/signed-model:v1
```

> The helper script `./scripts/sign-model.sh` wraps the keygen, sign, verify, and
> archive steps. Run `./scripts/sign-model.sh help` for usage.

### Configure in values.yaml

**Key-based verification** (recommended for air-gapped or private models):

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

**Sigstore keyless verification** (ties to an OIDC identity — no key management):

```yaml
signing:
  enabled: true
  signaturePath: "model.sig"
  ignoreGitPaths: true
  certificateIdentity: "user@example.com"
  certificateOidcIssuer: "https://accounts.google.com"
```

### How It Works on Deploy

On `helm install`:

1. Helm creates the **ModelValidation CR**, **signing-pubkey Secret**,
   **ServingRuntime**, and **InferenceService**
2. When the predictor pod is created, the operator's webhook detects the
   `validation.ml.sigstore.dev/ml` label and injects a `model-validation` init
   container that inherits all volume mounts from the main containers
3. The init container runs the verification agent — on success, the pod proceeds
   to start vLLM; on failure, the pod stays in `Init:Error` and the model is
   never served

### Helm Resources Created

| Resource | Purpose |
|---|---|
| `Secret/model-signing-pubkey` | Public key for verification (key-based only) |
| `ModelValidation/<name>-validation` | Tells operator how to verify the model |
| `InferenceService` | Predictor pod with `validation.ml.sigstore.dev/ml` label |
| `ServingRuntime` | vLLM runtime with PVC + key volume mounts |

### Testing Model Validation

See [Validate model signing](#validate-model-signing) in the Deploy section for
the full 6-step validation procedure with expected outputs.

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
