# Model Signing & Validation — End-to-End Report

## Environment

| Component | Value |
|---|---|
| Cluster | OpenShift 4.16+ with OpenShift AI |
| Namespace | `hr-assistant` |
| Model | Qwen/Qwen2.5-0.5B-Instruct (signed, packaged as OCI image) |
| Operator | Model Validation Operator v0.0.4-fix (`quay.io/rocrisp/model-validation-operator:v0.0.4-fix2`) |
| Agent | `quay.io/rocrisp/model-validation-agent:v0.0.4-fix` |
| Signed model image | `quay.io/rocrisp/qwen25-05b-signed:v2` |
| Verification method | Public key (EC P-256) |

## Bug Fix Applied

The upstream [sigstore/model-validation-operator](https://github.com/sigstore/model-validation-operator)
has a bug in its webhook handler (`internal/webhooks/pod_webhook.go`, lines 123-126). When the
webhook injects a model-validation init container, it copies volume mounts from **all** existing
containers without deduplication. In KServe/ODH environments, the `kserve-container` and injected
`agent` container both mount `/mnt/models`, causing the init container to have duplicate mounts.
Kubernetes rejects this with `"Invalid value: must be unique"`.

**Fix:** Added a `deduplicateVolumeMounts()` function that filters by `mountPath`, keeping the first
occurrence. The fix lives in the fork at [rocrisp/model-validation-operator](https://github.com/rocrisp/model-validation-operator).

---

## Step 1 — Verify the Operator is Running

**Commands:**

```bash
oc get pods -n model-validation-operator-system
oc get crd modelvalidations.ml.sigstore.dev
oc get mutatingwebhookconfiguration | grep validation
```

**Expected output:**

```
model-validation-controller-manager-8d4bb5d49-78tj6   1/1   Running   0   122m

modelvalidations.ml.sigstore.dev   2026-04-07T17:32:57Z

pods.validation.ml.sigstore.dev-98ft7   1   23h
```

**What happened:** The fixed operator pod is running, the `ModelValidation` CRD is registered, and
the mutating webhook is active. The operator watches for pods with the
`validation.ml.sigstore.dev/ml` label.

---

## Step 2 — Deploy with Helm

**Command:**

```bash
helm install hr-assistant helm/ -n hr-assistant
```

**Expected output:**

```
STATUS: deployed
```

**What happened:** Helm executed in this order:

1. Pre-install hook (weight -10): Created `model-storage` PVC (2Gi)
2. Pre-install hook (weight -5): Ran `model-download` Job — copied signed model from OCI image to PVC
3. Regular resources: Created `ModelValidation` CR, `signing-pubkey` Secret, `ServingRuntime`,
   `InferenceService`, AnythingLLM workbench

---

## Step 3 — Verify the Model Download

**Command:**

```bash
oc logs -n hr-assistant job/model-download
```

**Expected output:**

```
Copying signed model files to PVC...
Contents:
-rw-r--r--  config.json
-rw-r--r--  generation_config.json
-rw-r--r--  merges.txt
-rw-r--r--  model.safetensors    (988 MB)
-rw-r--r--  model.sig            (6,367 bytes)
-rw-r--r--  tokenizer.json
-rw-r--r--  tokenizer_config.json
-rw-r--r--  vocab.json
Found signature at /data/model.sig
```

**What happened:** The `model-download` Job ran a container from `quay.io/rocrisp/qwen25-05b-signed:v2`
(a busybox image with model files at `/model/`). It copied all files to the PVC mounted at `/data/`
and confirmed the signature file `model.sig` exists.

---

## Step 4 — Verify the Operator Webhook Injected the Init Container

**Command:**

```bash
oc logs -n model-validation-operator-system deployment/model-validation-controller-manager --tail=15
```

**Expected output (key lines):**

```
INFO  admission  Checking pod labels  {"labels": {..., "validation.ml.sigstore.dev/ml":"qwen25-05b-validation"}}
INFO  admission  ModelValidation label found, proceeding with injection
INFO  admission  Search associated Model Validation CR  {"modelValidationName": "qwen25-05b-validation"}
INFO  admission  construct args
INFO  admission  found public-key config
INFO  Updated ModelValidation status  {"injectedPods": 1, "authMethod": "public-key"}
```

**What happened:** When the predictor pod was created, the operator's mutating webhook:

1. Detected the `validation.ml.sigstore.dev/ml: qwen25-05b-validation` label
2. Found the `ModelValidation` CR named `qwen25-05b-validation`
3. Identified `publicKeyConfig` (key-based verification)
4. Injected a `model-validation` init container with the agent image and verification args
5. The init container inherited all volume mounts (model PVC + signing key Secret) from
   the main containers — deduplicated by the bug fix to avoid duplicate `/mnt/models` mounts

---

## Step 5 — Verify the Signature Check Passed

**Command:**

```bash
oc logs -n hr-assistant -l serving.kserve.io/inferenceservice=qwen25-05b-cpu -c model-validation
```

**Expected output:**

```json
{"level":"info","msg":"Starting validation agent","interval":0}
{"level":"info","msg":"Running initial validation"}
{"level":"info","msg":"Starting health server","address":":8080"}
{"level":"info","msg":"Verification succeeded"}
{"level":"info","msg":"Initial validation successful"}
{"level":"info","msg":"One-shot validation complete, exiting"}
{"level":"info","msg":"Shutting down health server"}
```

**What happened:** The `model-validation` init container:

1. Started the validation agent binary (`/usr/local/bin/validation-agent`)
2. Read the public key from `/keys/signing-key.pub` (mounted from the `model-signing-pubkey` Secret)
3. Read the signature from `/data/signed-model/model.sig`
4. Verified all model files under `/data/signed-model` against the signature
5. **Verification succeeded** — the model is cryptographically intact
6. Exited, allowing the main containers to start

---

## Step 6 — Verify Pod Structure (No Duplicate Mount Bug)

**Command:**

```bash
oc get pods -n hr-assistant -l serving.kserve.io/inferenceservice=qwen25-05b-cpu \
    -o jsonpath='{range .items[0].spec.initContainers[*]}{.name}{"\n"}{end}'
```

**Expected output:**

```
model-validation
```

**Command:**

```bash
oc get pods -n hr-assistant --no-headers
```

**Expected output:**

```
anythingllm-0                               3/3   Running     0     2m36s
anythingllm-seed-lbrf6                      0/1   Completed   0     2m38s
model-download-2s8tg                        0/1   Completed   0     2m48s
qwen25-05b-cpu-predictor-5bd748764d-rd4sb   2/2   Running     0     2m37s
```

**What happened:** The predictor pod has 1 init container (`model-validation`) and 2 main containers
(`kserve-container` + `agent`). No `CreateContainerError` from duplicate volume mounts — the
`deduplicateVolumeMounts()` fix in the operator correctly merged the overlapping `/mnt/models`
mounts from both containers.

---

## Step 7 — Verify Model Loaded from PVC (Not HuggingFace)

**Command:**

```bash
oc exec -n hr-assistant anythingllm-0 -c anythingllm -- \
    curl -s http://qwen25-05b-cpu-predictor:8080/v1/models | python3 -m json.tool
```

**Expected output:**

```json
{
    "data": [{
        "id": "qwen25-05b",
        "root": "/data/signed-model",
        "max_model_len": 2048
    }]
}
```

**What happened:** vLLM is serving the model from `root: "/data/signed-model"` — the PVC path
containing the verified model. It did not download from HuggingFace.

---

## Step 8 — Test Inference

**Command:**

```bash
oc exec -n hr-assistant anythingllm-0 -c anythingllm -- \
    curl -s http://qwen25-05b-cpu-predictor:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen25-05b","messages":[{"role":"user","content":"What is HR compliance in one sentence?"}],"max_tokens":50}'
```

**Expected output:**

```json
{
    "model": "qwen25-05b",
    "choices": [{
        "message": {
            "role": "assistant",
            "content": "HR compliance refers to the adherence to relevant labor laws and regulations, as well as the internal policies and procedures of an organization, in order to ensure the ethical and legal framework supporting the organization's values and objectives."
        },
        "finish_reason": "stop"
    }]
}
```

**What happened:** The cryptographically verified model served a correct inference response.

---

## Summary

| Step | Command | Outcome |
|---|---|---|
| Operator running | `oc get pods -n model-validation-operator-system` | 1/1 Running |
| Helm install | `helm install hr-assistant helm/ -n hr-assistant` | deployed |
| Model download | `oc logs job/model-download` | `Found signature at /data/model.sig` |
| Webhook injection | `oc logs deployment/model-validation-controller-manager` | `injectedPods: 1, authMethod: public-key` |
| Signature verification | `oc logs -c model-validation` | **Verification succeeded** |
| Pod healthy | `oc get pods` | predictor 2/2 Running, no init errors |
| Model source | `curl .../v1/models` | `root: /data/signed-model` |
| Inference | `curl .../v1/chat/completions` | `finish_reason: stop` |
