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

<details>
<summary><strong>Hardware</strong></summary>

| | CPU | Memory | Storage | GPU |
|---|---|---|---|---|
| **Minimum** | 2 cores | 4 Gi | 5 Gi | None |
| **Recommended** | 8 cores | 8 Gi | 5 Gi | None |

Compiled for Intel CPUs. AVX512 BRGEMM optimizations are disabled by default for stability
(`VLLM_CPU_DISABLE_AVX512=1`).

Example AWS instance: [m6i.4xlarge](https://instances.vantage.sh/aws/ec2/m6i.4xlarge) (16 vCPU, 64 GiB)

</details>

<details>
<summary><strong>Software</strong></summary>

- Red Hat OpenShift 4.16.24+
- Red Hat OpenShift AI 2.16.2+
- [Single-model server dependencies](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.16/html/installing_and_uninstalling_openshift_ai_self-managed/installing-the-single-model-serving-platform_component-install#configuring-automated-installation-of-kserve_component-install):
  - Red Hat OpenShift Service Mesh
  - Red Hat OpenShift Serverless
- [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
  for cryptographic model verification at deployment time

</details>

**Permissions:** Standard user. No elevated cluster permissions required.

## Deploy

### Prerequisites

<details>
<summary><strong>1. OpenShift AI Installed and Configured</strong></summary>

- Red Hat OpenShift AI 2.16.2+ with single-model serving platform:
  - Red Hat OpenShift Service Mesh
  - Red Hat OpenShift Serverless (KServe)

</details>

<details>
<summary><strong>2. Data Science Gateway</strong></summary>

```bash
oc get gateway data-science-gateway -n openshift-ingress
```

Expected output should show the gateway in `PROGRAMMED` state.

</details>

<details>
<summary><strong>3. AnythingLLM ImageStream (REQUIRED)</strong></summary>

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

</details>

<details>
<summary><strong>4. Storage Class</strong></summary>

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

</details>

<details>
<summary><strong>5. Model Validation Operator</strong></summary>

Install the operator that enforces model signature verification:

```bash
oc apply -k https://github.com/sigstore/model-validation-operator/config/overlays/olm
```

Verify it's running:

```bash
oc get pods -n model-validation-operator-system
oc get crd modelvalidations.ml.sigstore.dev
```

</details>

<details>
<summary><strong>6. Signed Model</strong></summary>

This project uses a HuggingFace model (default: `Qwen/Qwen2.5-0.5B-Instruct`)
that is downloaded locally, cryptographically signed using
[sigstore/model-transparency](https://github.com/sigstore/model-transparency),
and uploaded back to HuggingFace as a signed model. The signed model is then
referenced at [install time](#install-with-helm) via `--set model.storageUri`.

Follow the [Signing Guide](docs/SIGNING-GUIDE.md) for the complete workflow.

</details>

### Clone

```bash
git clone https://github.com/rocrisp/llm-cpu-serving.git && \
    cd llm-cpu-serving/
```

> This is a fork of [rh-ai-quickstart/llm-cpu-serving](https://github.com/rh-ai-quickstart/llm-cpu-serving).
> See [CHANGES.md](CHANGES.md) for modifications.

### Portability Checklist

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
    --set model.storageUri=hf://YOUR_HF_USERNAME/signed-model \
    --set signing.certificateIdentity="YOUR_EMAIL" \
    --set signing.certificateOidcIssuer="https://github.com/login/oauth"
```

Replace `YOUR_HF_USERNAME` with the HuggingFace username and `YOUR_EMAIL` with
the identity you used when signing the model in the
[Signing Guide](docs/SIGNING-GUIDE.md).

<details>
<summary><strong>Verification mode options</strong></summary>

**Keyless (OIDC) verification** — the default, shown above. Common OIDC issuers:

| Provider | `certificateOidcIssuer` |
|---|---|
| GitHub | `https://github.com/login/oauth` |
| Google | `https://accounts.google.com` |
| Microsoft | `https://login.microsoftonline.com` |

**Key-based verification** — for air-gapped or private models, pass the public key
instead of an OIDC identity:

```bash
helm install ${PROJECT} helm/ --namespace ${PROJECT} \
    --set signing.enabled=true \
    --set model.storageUri=hf://YOUR_HF_USERNAME/signed-model \
    --set-file signing.publicKeyData=signing-key.pub
```

See [`helm/values.yaml`](helm/values.yaml) for all signing options.

</details>

Helm executes in this order:

1. **Main resources** — creates the `ModelValidation` CR, `ServingRuntime`,
   `InferenceService`, AnythingLLM workbench, and supporting resources
2. **Operator webhook** — the Model Validation Operator detects the predictor pod
   and injects a `model-validation` init container that verifies the signature

### Wait for pods

```bash
oc -n ${PROJECT} get pods -w
```

<details>
<summary><strong>Expected output</strong></summary>

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

</details>

### Test

#### Access the UI

```bash
oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}' && echo
```

Navigate to **Projects** → **hr-assistant** → open the **AnythingLLM** workbench → click the **Assistant to the HR Representative** workspace.

![OpenShift AI Projects](docs/images/rhoai-1.png)

![OpenShift AI Projects](docs/images/rhoai-2.png)

**Direct Access URL:**

```bash
echo "https://$(oc get route data-science-gateway -n openshift-ingress -o jsonpath='{.spec.host}')/notebook/${PROJECT}/anythingllm/"
```

<details>
<summary><strong>Test the API directly</strong></summary>

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

</details>

<details>
<summary><strong>Validate model signing (end-to-end check)</strong></summary>

Run these checks after deploying to confirm the signing and verification flow:

```bash
PROJECT="hr-assistant"
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

# Step 1: Confirm that Kserve downloaded the model
echo "=== Step 1: Model downloaded ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c storage-initializer

# Step 2: Check verification succeeded
echo "=== Step 2: Verification result ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation
# Expected: "Verification succeeded"

# Step 3: Confirm model is loaded
echo "=== Step 3: Model source ==="
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c kserve-container | head -5
# Expected: model path shows /mnt/models

# Step 4: Test inference through the verified model
echo "=== Step 4: Inference test ==="
oc exec -n ${PROJECT} anythingllm-0 -c anythingllm -- \
    curl -s http://${MODEL_NAME}-cpu-predictor:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":30}"
# Expected: JSON response with choices[0].message.content
```

All steps passing confirms: the signed model was downloaded, the operator
injected the verification init container, the signature was verified, and the
model is serving traffic through the verified path.

</details>

### Delete

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
```

## Switching Models

<details>
<summary><strong>How to switch to a different model</strong></summary>

Follow the [Signing Guide](docs/SIGNING-GUIDE.md) to download, sign, and upload
the new model to HuggingFace, then reinstall:

```bash
helm uninstall ${PROJECT} --namespace ${PROJECT}
helm install ${PROJECT} helm/ --namespace ${PROJECT} \
  --set signing.enabled=true \
  --set model.name="<short-name>" \
  --set model.storageUri="hf://YOUR_HF_USERNAME/<model-name>-signed" \
  --set signing.certificateIdentity="YOUR_EMAIL" \
  --set signing.certificateOidcIssuer="https://github.com/login/oauth"
```

**Recommended CPU-friendly models:**

| Model | Parameters | Notes |
|---|---|---|
| `Qwen/Qwen2.5-0.5B-Instruct` | 0.5B | Good balance of quality and speed (default) |
| `HuggingFaceTB/SmolLM2-135M-Instruct` | 135M | Smallest, fastest |
| `HuggingFaceTB/SmolLM2-360M-Instruct` | 360M | Good balance |
| `HuggingFaceTB/SmolLM2-1.7B-Instruct` | 1.7B | Best quality, more resources |
| `TinyLlama/TinyLlama-1.1B-Chat-v1.0` | 1.1B | Alternative option |

</details>

## Vector DB Attestation and Integrity (Optional)

<details>
<summary><strong>Enable and configure vector DB integrity checking</strong></summary>

When `attestation.enabled: true`, the chart creates a baseline SHA-512 hash of the
LanceDB vector database after document seeding and periodically verifies it hasn't
been tampered with.

**Enable in values.yaml:**

```yaml
attestation:
  enabled: true
  schedule: "0 */6 * * *"    # check every 6 hours
  vectorDbPath: "/opt/app-root/src/anythingllm/storage/lancedb"
```

**How it works:**

1. **Attestation** (post-install hook): After documents are seeded, a Job computes
   SHA-512 of all LanceDB files and stores the hash in a `vectordb-attestation` ConfigMap.
2. **Integrity CronJob**: Runs on schedule, re-computes the hash, and compares it
   against the baseline. Results (`PASS`/`FAIL`) are written to the ConfigMap.

**Check integrity status:**

```bash
oc get configmap vectordb-attestation -n ${PROJECT} -o yaml
```

Key fields: `baseline-hash`, `last-check`, `last-result` (`PASS`/`FAIL`/`ERROR`).

</details>

## Troubleshooting

<details>
<summary><strong>Workbench shows "Notebook image deleted"</strong></summary>

The ImageStream `custom-anythingllm` is missing. See [Prerequisites](#3-anythingllm-imagestream-required).

</details>

<details>
<summary><strong>Workbench not accessible / "no healthy upstream"</strong></summary>

```bash
oc get pod anythingllm-0 -n ${PROJECT}           # should show 3/3 Running
oc get svc -n ${PROJECT}                          # should show anythingllm services
```

</details>

<details>
<summary><strong>vLLM pod not starting</strong></summary>

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

oc logs -n ${PROJECT} $(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o name) -c kserve-container
oc describe pod -n ${PROJECT} $(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o name)
```

</details>

<details>
<summary><strong>Port-forward or curl fails</strong></summary>

```bash
MODEL_NAME=$(grep '^  name:' helm/values.yaml | awk '{print $2}' | tr -d '"')

oc get pods -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor
POD=$(oc get pod -n ${PROJECT} -l app=isvc.${MODEL_NAME}-cpu-predictor -o jsonpath='{.items[0].metadata.name}')
oc port-forward -n ${PROJECT} pod/${POD} 8080:8080
```

</details>

<details>
<summary><strong>Vector DB integrity check fails</strong></summary>

```bash
# Check CronJob logs
oc logs -n ${PROJECT} job/$(oc get jobs -n ${PROJECT} -l app=vectordb-integrity --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)

# View attestation state
oc get configmap vectordb-attestation -n ${PROJECT} -o jsonpath='{.data}' | python3 -m json.tool
```

If `last-result` is `FAIL`, the vector DB was modified after attestation. This could be
a legitimate document update or an integrity violation. Re-attest after any intentional
change by deleting and re-running the attestation Job.

</details>

<details>
<summary><strong>Model validation init container fails</strong></summary>

```bash
# Check the init container logs
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c model-validation

# Check the storage-initializer (model download)
oc logs -n ${PROJECT} -l serving.kserve.io/inferenceservice -c storage-initializer

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

</details>

<details>
<summary><strong>Operator webhook not injecting init container</strong></summary>

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

</details>

<details>
<summary><strong>Storage issues</strong></summary>

```bash
oc get storageclass
oc get pvc -n ${PROJECT}
oc describe pvc anythingllm -n ${PROJECT}
```

Update `storageClassName` in [`helm/values.yaml`](helm/values.yaml) if needed.

</details>

## References

<details>
<summary><strong>Supply Chain Security</strong></summary>

- Model Validation Operator: [sigstore/model-validation-operator](https://github.com/sigstore/model-validation-operator)
- Model signing: [sigstore/model-transparency](https://github.com/sigstore/model-transparency)
- Sigstore: [sigstore.dev](https://www.sigstore.dev)

</details>

<details>
<summary><strong>Runtime & Infrastructure</strong></summary>

- Runtime: [vLLM CPU](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html)
- Runtime image: [quay.io/rh-aiservices-bu/vllm-cpu-openai-ubi9](https://quay.io/repository/rh-aiservices-bu/vllm-cpu-openai-ubi9)
- Runtime code: [github.com/rh-aiservices-bu/llm-on-openshift](https://github.com/rh-aiservices-bu/llm-on-openshift/tree/main/serving-runtimes/vllm_runtime)
- AnythingLLM: [Mintplex-Labs/anything-llm](https://github.com/Mintplex-Labs/anything-llm)

</details>

<details>
<summary><strong>Fork Information</strong></summary>

- Original: [rh-ai-quickstart/llm-cpu-serving](https://github.com/rh-ai-quickstart/llm-cpu-serving)
- This fork: [rocrisp/llm-cpu-serving](https://github.com/rocrisp/llm-cpu-serving)
- Changelog: [CHANGES.md](CHANGES.md)

</details>

## Tags

- **Industry:** Adopt and scale AI
- **Product:** OpenShift AI
- **Use case:** Productivity
