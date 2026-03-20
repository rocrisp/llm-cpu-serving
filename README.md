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

This chart supports [Sigstore cosign](https://github.com/sigstore/cosign) verification of OCI
model artifacts before inference. When enabled, a Helm pre-install hook verifies the model
signature and aborts deployment if it fails.

### Quick Start

```bash
# 1. Install cosign (https://github.com/sigstore/cosign#installation)

# 2. Generate a keypair
./scripts/sign-model.sh generate-keys

# 3. Push your model to an OCI registry
./scripts/sign-model.sh push ./model-files quay.io/your-org/qwen25-05b:v1

# 4. Sign the artifact
./scripts/sign-model.sh sign quay.io/your-org/qwen25-05b:v1

# 5. Encode the public key for values.yaml
./scripts/sign-model.sh encode-pubkey
```

### Enable in values.yaml

```yaml
model:
  storageUri: "oci://quay.io/your-org/qwen25-05b:v1"
  name: "qwen25-05b"
  maxModelLen: 2048

signing:
  enabled: true
  publicKey: "<base64-encoded cosign.pub>"
```

For keyless (OIDC) verification, leave `publicKey` empty and set:

```yaml
signing:
  enabled: true
  certificateIdentity: "user@example.com"
  certificateOidcIssuer: "https://accounts.google.com"
```

On `helm install`, a verification Job runs before any resources are created. If the
signature is invalid, the install fails and no InferenceService is deployed.

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

### Cosign verification fails during install

```bash
# Check the verification Job logs
oc logs -n ${PROJECT} job/cosign-verify-model

# Verify locally
cosign verify --key cosign.pub <your-oci-model-ref>
```

Common causes: wrong public key, unsigned artifact, or registry authentication issues.

### Storage issues

```bash
oc get storageclass
oc get pvc -n ${PROJECT}
oc describe pvc anythingllm -n ${PROJECT}
```

Update `storageClassName` in [`helm/values.yaml`](helm/values.yaml) if needed.

## References

**Supply Chain Security:**

- Sigstore cosign: [sigstore/cosign](https://github.com/sigstore/cosign)
- Model signing: [sigstore/model-transparency](https://github.com/sigstore/model-transparency)
- ORAS (OCI Registry As Storage): [oras.land](https://oras.land)

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
