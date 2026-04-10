# Changes from Original Repository

Original repo: https://github.com/rh-ai-quickstart/llm-cpu-serving.git

## Summary

Switched the default model to Qwen2.5-0.5B-Instruct, added CPU optimizations,
fixed AnythingLLM integration, added model signing and verification via the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator),
and added vector DB attestation.

---

## Model Change

| | Original | Current |
|---|---|---|
| Model | `oci://quay.io/rh-aiservices-bu/tinyllama:1.0` | `hf://Qwen/Qwen2.5-0.5B-Instruct` |
| Parameters | 1.1B | 0.5B |
| Name | `tinyllama` | `qwen25-05b` |
| Chat template | External ConfigMap | Built-in (Qwen has native chat template) |

## Files Modified

### `helm/values.yaml`
- Model changed to `hf://Qwen/Qwen2.5-0.5B-Instruct`
- Added `signing` section for Model Validation Operator integration
- Added `attestation` section for vector DB integrity checking
- Storage class set to `gp3-csi`

### `helm/templates/servingruntime.yaml`
- Model loaded from `/mnt/models` (KServe storageUri handles download)
- CPU optimizations: `--dtype float32`, `VLLM_CPU_DISABLE_AVX512=1`
- Conditional volume mounts for signing key Secret (when `publicKeyData` is set)

### `helm/templates/inferenceservice.yaml`
- Resource names templated from `model.name`
- Added `validation.ml.sigstore.dev/ml` label on predictor pods (triggers operator webhook)

### `helm/templates/anythingllm-secret.yaml`
- Provider changed from `localai` to `generic-openai`
- Service URL and model name templated from `model.name`

### `helm/templates/workbench.yaml`
- Updated image to use internal ImageStream (`custom-anythingllm`)
- Removed manual OAuth proxy (now auto-injected by OpenShift AI controller)
- Added `notebooks.opendatahub.io/inject-auth: 'true'` annotation

## Files Created

### Model Signing & Verification
- `helm/templates/model-validation-cr.yaml` — `ModelValidation` custom resource for the operator
- `helm/templates/signing-pubkey-secret.yaml` — Public key Secret for key-based verification
- `docs/SIGNING-GUIDE.md` — Step-by-step guide for signing and uploading models

### Vector DB Attestation
- `helm/templates/vectordb-attestation-job.yaml` — Post-install hook for baseline hash
- `helm/templates/vectordb-attestation-configmap.yaml` — Stores baseline and check results
- `helm/templates/vectordb-integrity-cronjob.yaml` — Periodic integrity verification
- `helm/templates/vectordb-attestation-rbac.yaml` — RBAC for integrity checks

### Supporting Files
- `helm/templates/anythingllm-api-service.yaml` — Internal API service for seed Job
- `helm/templates/anythingllm-networkpolicy.yaml` — Network policy for workbench
- `helm/templates/anythingllm-serviceaccount.yaml` — ServiceAccount for workbench
- `helm/templates/vllm-chat-template-configmap.yaml` — Chat template ConfigMap
- `scripts/verify-prerequisites.sh` — Cluster prerequisites checker

### Documentation
- `ARCHITECTURE.md` — Detailed component architecture
- `DEPLOYMENT-GUIDE.md` — Cross-cluster deployment guide
- `BLOG.md` — Beginner's guide to running LLMs on CPU

## Files Removed (from original)
- `helm/templates/anythingllm-oauth-secret.yaml` — Not needed (controller manages OAuth)
- `helm/templates/anythingllm-tls-service.yaml` — Not needed (controller creates services)
- `helm/templates/anythingllm-imagestream.yaml` — ImageStream managed externally
- `helm/templates/modelcar-dataconnection.yaml` — Old TinyLlama OCI data connection (no longer used)

## Key Architecture Decisions

1. **Model Validation Operator** — Model signing verification uses the
   [sigstore/model-validation-operator](https://github.com/sigstore/model-validation-operator)
   webhook to inject a verification init container into predictor pods, rather than
   a standalone Helm pre-install Job. This provides runtime enforcement (pods cannot
   start without passing verification).

2. **CPU optimizations** — `float32` dtype and `VLLM_CPU_DISABLE_AVX512=1` prevent
   crashes on CPU inference.

3. **OpenShift AI controller integration** — The workbench uses annotations to trigger
   auto-injection of `kube-rbac-proxy` sidecar and auto-creation of services/routes,
   reducing the number of Helm-managed resources.
