# Architecture

This document describes the detailed component architecture of the HR Assistant deployment.
All resource names containing a model identifier (shown as `<model.name>` below) are derived
from the `model.name` field in [`helm/values.yaml`](helm/values.yaml).

## Detailed Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          OpenShift AI / OpenShift Cluster                       │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    Namespace: hr-assistant                              │    │
│  │                                                                         │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │  User Interface Layer                                            │   │    │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │   │    │
│  │  │  │  Data Science Gateway (OpenShift Route)                    │  │   │    │
│  │  │  │  https://data-science-gateway.apps.../hr-assistant/...     │  │   │    │
│  │  │  └─────────────────────┬──────────────────────────────────────┘  │   │    │
│  │  │                        │                                         │   │    │
│  │  │                        ▼                                         │   │    │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │   │    │
│  │  │  │  AnythingLLM Workbench (StatefulSet)                       │  │   │    │
│  │  │  │  Pod: anythingllm-0                                        │  │   │    │
│  │  │  │  ┌──────────────────────────────────────────────────────┐  │  │   │    │
│  │  │  │  │  Container: kube-rbac-proxy (auto-injected)          │  │  │   │    │
│  │  │  │  │  Port: 8443 (HTTPS with RBAC authentication)         │  │  │   │    │
│  │  │  │  │  Note: Injected by OpenShift AI controller           │  │  │   │    │
│  │  │  │  └───────────────────┬──────────────────────────────────┘  │  │   │    │
│  │  │  │                      │                                     │  │   │    │
│  │  │  │  ┌───────────────────▼──────────────────────────────────┐  │  │   │    │
│  │  │  │  │  Container: anythingllm                              │  │  │   │    │
│  │  │  │  │  Port: 8888 (Jupyter/AnythingLLM interface)          │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  Features:                                           │  │  │   │    │
│  │  │  │  │  • Chat interface for end users                      │  │  │   │    │
│  │  │  │  │  • Document embedding (native embedder)              │  │  │   │    │
│  │  │  │  │  • Vector database (LanceDB)                         │  │  │   │    │
│  │  │  │  │  • RAG (Retrieval-Augmented Generation)              │  │  │   │    │
│  │  │  │  │  • Workspace: "Assistant to the HR Representative"   │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  Environment (from Secret: <model.name>-vllm-cpu):   │  │  │   │    │
│  │  │  │  │  • LLM_PROVIDER: generic-openai                      │  │  │   │    │
│  │  │  │  │  • GENERIC_OPEN_AI_BASE_PATH:                        │  │  │   │    │
│  │  │  │  │      http://<model.name>-cpu-predictor:8080/v1       │  │  │   │    │
│  │  │  │  │  • GENERIC_OPEN_AI_MODEL_PREF: <model.name>          │  │  │   │    │
│  │  │  │  │  • EMBEDDING_ENGINE: native                          │  │  │   │    │
│  │  │  │  │  • VECTOR_DB: lancedb                                │  │  │   │    │
│  │  │  │  └───────────────────┬──────────────────────────────────┘  │  │   │    │
│  │  │  │                      │                                     │  │   │    │
│  │  │  │  ┌───────────────────▼──────────────────────────────────┐  │  │   │    │
│  │  │  │  │  Container: anythingllm-automation (sidecar)         │  │  │   │    │
│  │  │  │  │  • SQLite database management                        │  │  │   │    │
│  │  │  │  │  • API key setup automation                          │  │  │   │    │
│  │  │  │  └──────────────────────────────────────────────────────┘  │  │   │    │
│  │  │  │                                                            │  │   │    │
│  │  │  │  Volumes:                                                  │  │   │    │
│  │  │  │  • PVC: anythingllm (persistent storage)                   │  │   │    │
│  │  │  │  • ConfigMap: workbench-trusted-ca-bundle                  │  │   │    │
│  │  │  │  • Secret: anythingllm-kube-rbac-proxy-tls (auto-created)  │  │   │    │
│  │  │  │  • ConfigMap: anythingllm-kube-rbac-proxy-config (auto)    │  │   │    │
│  │  │  └────────────────────────────────────────────────────────────┘  │   │    │
│  │  │                        │                                         │   │    │
│  │  │                        │ HTTP POST /v1/chat/completions          │   │    │
│  │  │                        │ (OpenAI-compatible API calls)           │   │    │
│  │  │                        │                                         │   │    │
│  │  └────────────────────────┼─────────────────────────────────────────┘   │    │
│  │                           │                                             │    │
│  │                           ▼                                             │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │  Inference Service Layer                                         │   │    │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │   │    │
│  │  │  │  Service: <model.name>-cpu-predictor                       │  │   │    │
│  │  │  │  Type: Headless (ClusterIP: None)                          │  │   │    │
│  │  │  │  Port: 80 → Target: 8080                                   │  │   │    │
│  │  │  └─────────────────────┬──────────────────────────────────────┘  │   │    │
│  │  │                        │                                         │   │    │
│  │  │                        ▼                                         │   │    │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │   │    │
│  │  │  │  InferenceService: <model.name>-cpu (KServe)               │  │   │    │
│  │  │  │  Deployment Mode: RawDeployment                            │  │   │    │
│  │  │  │  Runtime: vllm-cpu (ServingRuntime)                        │  │   │    │
│  │  │  │                                                            │  │   │    │
│  │  │  │  Pod: <model.name>-cpu-predictor-xxxxxxxxx-xxxxx           │  │   │    │
│  │  │  │  ┌──────────────────────────────────────────────────────┐  │  │   │    │
│  │  │  │  │  Container: agent (KServe Agent)                     │  │  │   │    │
│  │  │  │  │  • Model loading and lifecycle management            │  │  │   │    │
│  │  │  │  │  • Health checks and monitoring                      │  │  │   │    │
│  │  │  │  └───────────────────┬──────────────────────────────────┘  │  │   │    │
│  │  │  │                      │                                     │  │   │    │
│  │  │  │  ┌───────────────────▼──────────────────────────────────┐  │  │   │    │
│  │  │  │  │  Container: kserve-container (vLLM)                  │  │  │   │    │
│  │  │  │  │  Port: 8080 (HTTP)                                   │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  vLLM Server Configuration:                          │  │  │   │    │
│  │  │  │  │  • Model: from model.storageUri in values.yaml       │  │  │   │    │
│  │  │  │  │  • Dtype: float32 (CPU optimized)                    │  │  │   │    │
│  │  │  │  │  • Max model length: from model.maxModelLen          │  │  │   │    │
│  │  │  │  │  • Served model name: <model.name>                   │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  Environment Variables:                              │  │  │   │    │
│  │  │  │  │  • VLLM_CPU_DISABLE_AVX512=1                         │  │  │   │    │
│  │  │  │  │  • ONEDNN_VERBOSE=0                                  │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  API Endpoints:                                      │  │  │   │    │
│  │  │  │  │  • GET  /health                                      │  │  │   │    │
│  │  │  │  │  • GET  /v1/models                                   │  │  │   │    │
│  │  │  │  │  • POST /v1/chat/completions ← (Primary)             │  │  │   │    │
│  │  │  │  │  • POST /v1/completions                              │  │  │   │    │
│  │  │  │  │  • POST /v1/embeddings                               │  │  │   │    │
│  │  │  │  │                                                      │  │  │   │    │
│  │  │  │  │  Resources (from values.yaml):                       │  │  │   │    │
│  │  │  │  │  • Requests: 2 CPU, 4Gi memory                       │  │  │   │    │
│  │  │  │  │  • Limits: 8 CPU, 8Gi memory                         │  │  │   │    │
│  │  │  │  └───────────────────┬──────────────────────────────────┘  │  │   │    │
│  │  │  │                      │                                     │  │   │    │
│  │  │  │                      ▼                                     │  │   │    │
│  │  │  │  ┌──────────────────────────────────────────────────────┐  │  │   │    │
│  │  │  └────────────────────────────────────────────────────────────┘  │   │    │
│  │  └──────────────────────────────────────────────────────────────────┘   │    │
│  │                                                                         │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │  Supporting Resources                                            │   │    │
│  │  │                                                                  │   │    │
│  │  │  Helm-Managed Resources:                                         │   │    │
│  │  │  ├── ConfigMaps:                                                 │   │    │
│  │  │  │   • workbench-trusted-ca-bundle - CA certificates             │   │    │
│  │  │  │   • modelconfig-<model.name>-cpu-0 - Model configuration      │   │    │
│  │  │  ├── Secrets:                                                    │   │    │
│  │  │  │   • <model.name>-vllm-cpu - AnythingLLM LLM provider config   │   │    │
│  │  │  │   • anythingllm-api - API key for AnythingLLM                 │   │    │
│  │  │  ├── ServiceAccounts:                                            │   │    │
│  │  │  │   • anythingllm - Identity for AnythingLLM pod                │   │    │
│  │  │  ├── ServingRuntime:                                             │   │    │
│  │  │  │   • vllm-cpu - Defines vLLM container spec                    │   │    │
│  │  │  └── Jobs:                                                       │   │    │
│  │  │      • anythingllm-seed - Pre-seeds workspace with documents     │   │    │
│  │  │                                                                  │   │    │
│  │  │  Auto-Created by OpenShift AI Controller:                        │   │    │
│  │  │  ├── Services (with ownerReferences):                            │   │    │
│  │  │  │   • anythingllm - Port 80→8888 (main workbench)               │   │    │
│  │  │  │   • anythingllm-kube-rbac-proxy - Port 8443 (auth proxy)      │   │    │
│  │  │  ├── HTTPRoute (in redhat-ods-applications namespace):           │   │    │
│  │  │  │   • nb-hr-assistant-anythingllm                               │   │    │
│  │  │  │     Backend: anythingllm-kube-rbac-proxy:8443                 │   │    │
│  │  │  ├── ReferenceGrant:                                             │   │    │
│  │  │  │   • notebook-httproute-access (cross-namespace access)        │   │    │
│  │  │  ├── ConfigMaps:                                                 │   │    │
│  │  │  │   • anythingllm-kube-rbac-proxy-config                        │   │    │
│  │  │  └── Secrets:                                                    │   │    │
│  │  │      • anythingllm-kube-rbac-proxy-tls (TLS certificates)        │   │    │
│  │  └──────────────────────────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                 │
│  External Dependencies:                                                         │
│  • HuggingFace Hub: Model download (per model.storageUri)                       │
│  • Red Hat OpenShift Service Mesh: Networking and routing                       │
│  • Red Hat OpenShift Serverless (KServe): Model serving platform                │
│  • Model Validation Operator (model signature verification)                     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Request Flow

1. **User Request Flow:**
   User → Data Science Gateway → HTTPRoute → kube-rbac-proxy → AnythingLLM UI

2. **Chat Message Processing:**
   1. User sends message in AnythingLLM
   2. AnythingLLM embeds the query (native embedder)
   3. AnythingLLM searches vector DB (LanceDB) for relevant context
   4. AnythingLLM constructs chat completion request with context

3. **Inference Request:**

   ```
   AnythingLLM → POST http://<model.name>-cpu-predictor:8080/v1/chat/completions

   Request Body:
   {
     "model": "<model.name>",
     "messages": [
       {"role": "system", "content": "System prompt with HR context..."},
       {"role": "user", "content": "User question..."}
     ],
     "max_tokens": 512,
     "temperature": 0.7
   }
   ```

4. **vLLM Processing:**
   1. Receives request at `/v1/chat/completions` endpoint
   2. Applies chat template to convert messages to prompt
   3. Tokenizes prompt
   4. Runs inference on CPU (float32 dtype)
   5. Generates tokens autoregressively
   6. Returns streaming or complete response

5. **Response Path:**
   vLLM → `<model.name>-cpu-predictor` Service → AnythingLLM → User Interface

## Model Signing and Verification Flow

The chart integrates with the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator)
to enforce cryptographic model verification before the predictor pod serves traffic.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Model Signing and Verification Flow                                     │
│                                                                          │
│  Pre-install Hooks (Helm):                                               │
│  ┌────────────────────────────┐   ┌──────────────────────────────────┐  │
│  │ PVC: model-storage         │   │ Job: model-download              │  │
│  │ (hook-weight: -10)         │──▶│ Copies signed model from OCI     │  │
│  │ Persistent storage for     │   │ image to PVC at /data/signed-model│  │
│  │ verified model files       │   │ (hook-weight: -5)                │  │
│  └────────────────────────────┘   └──────────────────────────────────┘  │
│                                                                          │
│  Runtime Resources (Helm):                                               │
│  ┌────────────────────────────┐   ┌──────────────────────────────────┐  │
│  │ ModelValidation CR         │   │ Secret: model-signing-pubkey     │  │
│  │ (ml.sigstore.dev/v1alpha1) │   │ PEM-encoded public key for      │  │
│  │ Configures verification    │   │ key-based verification           │  │
│  │ method + model path        │   │ (optional — for key-based mode)  │  │
│  └────────────┬───────────────┘   └──────────────────────────────────┘  │
│               │                                                          │
│               ▼                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Model Validation Operator (cluster-scoped)                      │   │
│  │  Namespace: model-validation-operator-system                     │   │
│  │                                                                  │   │
│  │  MutatingWebhookConfiguration:                                   │   │
│  │  • Watches pods with label: validation.ml.sigstore.dev/ml        │   │
│  │  • Reads ModelValidation CR to get verification config           │   │
│  │  • Injects model-validation init container into predictor pod    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│               │                                                          │
│               ▼                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Predictor Pod (with injected init container)                    │   │
│  │                                                                  │   │
│  │  InitContainer: model-validation                                 │   │
│  │  ├── Reads public key from /keys/signing-key.pub                 │   │
│  │  ├── Reads model from /data/signed-model                         │   │
│  │  ├── Reads signature from /data/signed-model/model.sig           │   │
│  │  └── If verification FAILS → pod stays in Init:Error             │   │
│  │       If verification PASSES → pod proceeds to start             │   │
│  │                                                                  │   │
│  │  Container: kserve-container (vLLM)                              │   │
│  │  └── Loads verified model from /data/signed-model                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

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
