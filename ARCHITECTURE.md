# Architecture

This document describes the detailed component architecture of the HR Assistant deployment.
All resource names containing a model identifier (shown as `<model.name>` below) are derived
from the `model.name` field in [`helm/values.yaml`](helm/values.yaml).

## High-Level Overview

```mermaid
graph TB
    User([User]) --> Gateway[Data Science Gateway]

    subgraph cluster["OpenShift AI Cluster"]
        Gateway --> RBAC[kube-rbac-proxy<br/>auto-injected]

        subgraph ns["Namespace: hr-assistant"]
            subgraph workbench["AnythingLLM Workbench (StatefulSet)"]
                RBAC --> ALM[AnythingLLM<br/>Port 8888]
                ALM --> Sidecar[anythingllm-automation<br/>SQLite / API key setup]
            end

            ALM -->|POST /v1/chat/completions| Service

            subgraph inference["Inference Service Layer"]
                Service["Service: model-cpu-predictor<br/>Headless ClusterIP: None<br/>Port 80 → 8080"]
                Service --> Pod

                subgraph Pod["Predictor Pod"]
                    Init["InitContainer: model-validation<br/>Verifies model signature"]
                    Init -->|pass| Agent[Container: agent<br/>KServe Agent]
                    Agent --> VLLM["Container: kserve-container<br/>vLLM (CPU, float32)<br/>Port 8080"]
                end
            end

            subgraph signing["Model Signing Resources"]
                MVR[ModelValidation CR<br/>ml.sigstore.dev/v1alpha1]
                PubKey[Secret: model-signing-pubkey<br/>EC P-256 public key]
            end

            PubKey -->|/keys/signing-key.pub| Init
            MVR --> Operator
        end

        subgraph operator-ns["Namespace: model-validation-operator-system"]
            Operator[Model Validation Operator<br/>MutatingWebhookConfiguration]
        end

        Operator -->|injects init container| Pod
    end

    subgraph external["External Dependencies"]
        OSM[OpenShift Service Mesh]
        KServe[OpenShift Serverless / KServe]
    end

    style signing fill:#e8f5e9,stroke:#2e7d32
    style operator-ns fill:#fff3e0,stroke:#e65100
    style workbench fill:#e3f2fd,stroke:#1565c0
    style inference fill:#fce4ec,stroke:#c62828
```

## Deployment Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Helm
    participant KServe as KServe / storage-initializer
    participant HF as HuggingFace
    participant MVO as Model Validation Operator
    participant Pod as Predictor Pod
    participant vLLM

    Dev->>Helm: helm install hr-assistant helm/

    Note over Helm: Main resources
    Helm->>Helm: Create ModelValidation CR
    Helm->>Helm: Create signing-pubkey Secret
    Helm->>Helm: Create ServingRuntime + InferenceService

    Note over KServe: storage-initializer downloads model
    KServe->>HF: Download model via storageUri
    HF-->>KServe: Model files + model.sig → /mnt/models

    Note over MVO: Webhook intercepts pod creation
    MVO->>MVO: Detect validation.ml.sigstore.dev/ml label
    MVO->>MVO: Read ModelValidation CR
    MVO->>Pod: Inject model-validation init container

    Note over Pod: Init container runs
    Pod->>Pod: Read public key from /keys/signing-key.pub
    Pod->>Pod: Read model from /mnt/models
    Pod->>Pod: Verify signature (model.sig)

    alt Verification passes
        Pod->>vLLM: Start kserve-container
        vLLM->>vLLM: Load model from /mnt/models
        vLLM-->>Dev: Ready to serve (2/2 Running)
    else Verification fails
        Pod-->>Dev: Pod stays in Init:Error
    end
```

## Request Flow

```mermaid
sequenceDiagram
    participant User
    participant GW as Data Science Gateway
    participant RBAC as kube-rbac-proxy
    participant ALM as AnythingLLM
    participant LDB as LanceDB
    participant vLLM as vLLM (CPU)

    User->>GW: Chat message
    GW->>RBAC: Route via HTTPRoute
    RBAC->>ALM: Authenticated request

    ALM->>ALM: Embed query (native embedder)
    ALM->>LDB: Search for relevant context
    LDB-->>ALM: Matching document chunks

    ALM->>vLLM: POST /v1/chat/completions<br/>{model, messages + context, max_tokens}
    Note over vLLM: CPU inference (float32)<br/>~2-3 tokens/second
    vLLM-->>ALM: Generated response

    ALM-->>User: Answer with source citations
```

## Model Signing and Verification

```mermaid
graph LR
    subgraph sign["Developer Workstation"]
        Model[Model Files] --> Sign["model_signing sign<br/>(EC P-256 or keyless)"]
        Sign --> Sig[model.sig]
    end

    Model -->|hf upload| HF[(HuggingFace<br/>signed-model repo)]
    Sig -->|hf upload| HF

    HF -->|KServe storageUri| MntModels["/mnt/models"]

    subgraph verify["Predictor Pod (Init)"]
        MntModels --> Agent[model-validation<br/>init container]
        Key[Public Key<br/>from Secret] --> Agent
        Agent -->|signature valid| Pass[✓ Pod starts<br/>vLLM serves model]
        Agent -->|signature invalid| Fail[✗ Init:Error<br/>Model never served]
    end

    style sign fill:#e3f2fd,stroke:#1565c0
    style verify fill:#e8f5e9,stroke:#2e7d32
    style Fail fill:#ffcdd2,stroke:#c62828
    style Pass fill:#c8e6c9,stroke:#2e7d32
```

## Component Details

### AnythingLLM Workbench

| Property | Value |
|---|---|
| Type | StatefulSet (Pod: `anythingllm-0`) |
| Containers | `kube-rbac-proxy` (auto-injected), `anythingllm`, `anythingllm-automation` |
| Port | 8888 (AnythingLLM), 8443 (RBAC proxy) |
| Features | Chat UI, RAG, document embedding (native), LanceDB vector store |
| LLM Provider | `generic-openai` → `http://<model.name>-cpu-predictor:8080/v1` |
| Volumes | PVC `anythingllm`, CA bundle ConfigMap, auto-created TLS Secret |

### Predictor Pod

| Property | Value |
|---|---|
| Type | Deployment via KServe InferenceService (RawDeployment mode) |
| Init Container | `model-validation` — injected by Model Validation Operator |
| Containers | `agent` (KServe Agent), `kserve-container` (vLLM) |
| Port | 8080 (HTTP) |
| Model source | `/mnt/models` (downloaded via KServe storageUri, cryptographically verified) |
| vLLM config | `--dtype float32`, `VLLM_CPU_DISABLE_AVX512=1`, `ONEDNN_VERBOSE=0` |
| API endpoints | `GET /health`, `GET /v1/models`, `POST /v1/chat/completions`, `POST /v1/completions` |
| Resources | Requests: 2 CPU / 4Gi — Limits: 8 CPU / 8Gi |

### Model Validation Operator

| Property | Value |
|---|---|
| Namespace | `model-validation-operator-system` |
| Scope | Cluster-scoped (MutatingWebhookConfiguration) |
| Trigger | Pods with label `validation.ml.sigstore.dev/ml` |
| CRD | `ModelValidation` (`ml.sigstore.dev/v1alpha1`) |
| Action | Injects `model-validation` init container with verification agent |
| On pass | Init container exits 0, pod proceeds to start main containers |
| On fail | Init container exits non-zero, pod stays in `Init:Error` |

### Helm-Managed Resources

| Resource | Purpose |
|---|---|
| `ModelValidation/<name>-validation` | Configures signature verification |
| `Secret/model-signing-pubkey` | PEM-encoded public key for verification |
| `InferenceService/<name>-cpu` | KServe predictor with validation label |
| `ServingRuntime/vllm-cpu` | vLLM container spec |
| `Secret/<name>-vllm-cpu` | AnythingLLM LLM provider config |
| `Secret/anythingllm-api` | API key for AnythingLLM |
| `ServiceAccount/anythingllm` | Identity for AnythingLLM pod |
| `Job/anythingllm-seed` | Pre-seeds workspace with documents |

### Auto-Created by OpenShift AI Controller

| Resource | Purpose |
|---|---|
| `Service/anythingllm` | Port 80→8888 (main workbench) |
| `Service/anythingllm-kube-rbac-proxy` | Port 8443 (auth proxy) |
| `HTTPRoute/nb-hr-assistant-anythingllm` | Routes traffic from Data Science Gateway |
| `ReferenceGrant/notebook-httproute-access` | Cross-namespace access |
| `ConfigMap/anythingllm-kube-rbac-proxy-config` | RBAC proxy configuration |
| `Secret/anythingllm-kube-rbac-proxy-tls` | TLS certificates |

## Performance Characteristics

Performance varies depending on the model configured in `helm/values.yaml`. Below are
general guidelines for CPU inference with the default resource limits (8 CPU, 8Gi memory):

- **Inference Speed:** ~20-40 seconds for 50-100 tokens on 8 CPU cores
- **Throughput:** ~2-3 tokens/second on CPU
- **First response:** May take 30-60 seconds as the model processes context
- **Max Context:** Configured via `model.maxModelLen` in `values.yaml` (default: 2048 tokens)
- **Concurrency:** Supports multiple requests (CPU KV cache managed by vLLM)

Smaller models (135M-360M parameters) will be faster; larger models (1B+) will produce
higher quality responses but require more resources and time.
