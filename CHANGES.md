# Changes from Original Repository

Original repo: https://github.com/rh-ai-quickstart/llm-cpu-serving.git

## Summary
Converted the deployment from TinyLlama (1.1B parameters) to Facebook OPT-125m for faster CPU inference, added CPU optimizations, and fixed AnythingLLM integration.

---

## Files Modified

### 1. `helm/values.yaml`
**Changes:**
- Changed model from `oci://quay.io/rh-aiservices-bu/tinyllama:1.0` to `hf://facebook/opt-125m`
- Updated model name from `tinyllama` to `opt-125m`
- Kept max model length at 2048 tokens

```yaml
# Before:
model:
  storageUri: "oci://quay.io/rh-aiservices-bu/tinyllama:1.0"
  name: "tinyllama"
  maxModelLen: 2048

# After:
model:
  storageUri: "hf://facebook/opt-125m"
  name: "opt-125m"
  maxModelLen: 2048
```

### 2. `helm/templates/servingruntime.yaml`
**Changes:**
- Updated model loading to use HuggingFace model directly
- Added CPU-specific optimizations (dtype: float32)
- Added environment variables to disable problematic CPU optimizations
- Added chat template volume mount from ConfigMap
- Made model references use template variables

```yaml
# Key additions:
- args:
    - --model
    - {{ .Values.model.storageUri | trimPrefix "hf://" }}
    - --dtype
    - float32
    - --chat-template
    - /app/chat-template/template.jinja
  env:
    - name: VLLM_CPU_DISABLE_AVX512
      value: "1"
    - name: ONEDNN_VERBOSE
      value: "0"
  volumeMounts:
    - name: chat-template
      mountPath: /app/chat-template
      readOnly: true
volumes:
  - name: chat-template
    configMap:
      name: vllm-chat-template
```

### 3. `helm/templates/anythingllm-secret.yaml`
**Changes:**
- Changed LLM provider from `localai` to `generic-openai`
- Updated secret keys from `LOCAL_AI_*` to `GENERIC_OPEN_AI_*`
- Made model references dynamic using template variables
- Updated base64-encoded values for new service name and model

```yaml
# Before:
data:
  LLM_PROVIDER: bG9jYWxhaQ==  # localai
  LOCAL_AI_BASE_PATH: aHR0cDovL3RpbnlsbGFtYS0xYi1jcHUtcHJlZGljdG9yOjgwODAvdjE=
  LOCAL_AI_MODEL_PREF: dGlueWxsYW1h

# After:
data:
  LLM_PROVIDER: Z2VuZXJpYy1vcGVuYWk=  # generic-openai
  GENERIC_OPEN_AI_BASE_PATH: aHR0cDovL29wdC0xMjVtLWNwdS1wcmVkaWN0b3I6ODA4MC92MQ==
  GENERIC_OPEN_AI_MODEL_PREF: b3B0LTEyNW0=
  GENERIC_OPEN_AI_API_KEY: c2stZHVtbXk=
```

### 4. `helm/templates/inferenceservice.yaml`
**Changes:**
- Made InferenceService name dynamic based on model name
- Removed hardcoded storageUri (model loaded via ServingRuntime args)
- Updated display name to use template variable

```yaml
# Before:
metadata:
  name: tinyllama-1b-cpu
  annotations:
    openshift.io/display-name: tinyllama-1b-cpu
spec:
  predictor:
    model:
      storageUri: {{ .Values.model.storageUri | quote }}

# After:
metadata:
  name: {{ .Values.model.name }}-cpu
  annotations:
    openshift.io/display-name: {{ .Values.model.name }}-cpu
spec:
  predictor:
    model:
      # storageUri removed - loaded via ServingRuntime
```

### 5. `helm/templates/workbench.yaml`
**Changes:**
- Updated secret reference to use template variable

```yaml
# Before:
envFrom:
  - secretRef:
      name: tinyllama-vllm-cpu

# After:
envFrom:
  - secretRef:
      name: {{ .Values.model.name }}-vllm-cpu
```

### 6. `helm/templates/anythingllm-api.yaml`
**Changes:**
- Updated annotations to use template variables for model name

```yaml
# Before:
annotations:
  openshift.io/description: Connect to a tinyllama model
  openshift.io/display-name: vLLM CPU TinyLlama

# After:
annotations:
  openshift.io/description: Connect to a {{ .Values.model.name }} model
  openshift.io/display-name: vLLM CPU {{ .Values.model.name }}
```

---

## Files Created

### 1. `helm/templates/vllm-chat-template-configmap.yaml`
**Purpose:** Provides a Jinja2 chat template for models that don't have one built-in

**Content:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vllm-chat-template
  labels:
    app.kubernetes.io/managed-by: Helm
data:
  template.jinja: |-
    {{`{%- for message in messages -%}
    {%- if message['role'] == 'system' -%}
    {{ message['content'] }}

    {%- endif -%}
    {%- if message['role'] == 'user' -%}
    {{ message['content'] }}
    {%- endif -%}
    {%- if message['role'] == 'assistant' -%}
    {{ message['content'] }}
    {%- endif -%}
    {%- endfor -%}`}}
```

---

## Technical Details

### Why These Changes Were Made:

1. **Model Change (TinyLlama → OPT-125m)**
   - OPT-125m is 8-10x faster on CPU (125M vs 1.1B parameters)
   - More suitable for CPU-only inference environments
   - Still provides reasonable text generation quality

2. **CPU Optimizations**
   - `--dtype float32`: Prevents fp16-related crashes on CPU
   - `VLLM_CPU_DISABLE_AVX512=1`: Works around brgemm kernel issues
   - These prevent RuntimeError crashes during inference

3. **Chat Template**
   - OPT-125m doesn't have a built-in chat template
   - Required for `/v1/chat/completions` API endpoint
   - Mounted via ConfigMap for easy updates

4. **AnythingLLM Provider Change**
   - `generic-openai` provider handles OpenAI-compatible APIs better
   - Provides better error handling and compatibility
   - Required for proper chat completions integration

### Performance Characteristics:

- **Model Size:** 125M parameters (vs 1.1B for TinyLlama)
- **Inference Speed:** ~20-25 seconds for 50 tokens on CPU
- **Memory Usage:** ~2-4GB (vs 4-8GB for TinyLlama)
- **Quality:** Lower than TinyLlama but acceptable for demos/testing

### Service Endpoints:

- InferenceService: `opt-125m-cpu-predictor.hr-assistant.svc.cluster.local:8080`
- API Endpoints: `/v1/completions`, `/v1/chat/completions`
- AnythingLLM: Accessible via OpenShift Data Science Gateway

---

## Deployment Notes:

The deployment now uses:
- **Namespace:** `hr-assistant`
- **Release Name:** `hr-assistant`
- **Model:** facebook/opt-125m from HuggingFace
- **Runtime:** vLLM 0.7.3 (CPU-optimized)
- **Workbench:** AnythingLLM 1.9.1

All resource names are now templated and will automatically update based on the model name in `values.yaml`.

---

## Future Improvements:

To switch to a different model:
1. Update `model.storageUri` in `values.yaml` (use `hf://` prefix for HuggingFace)
2. Update `model.name` to match the model
3. Verify the model has a chat template or update the ConfigMap
4. Run `helm upgrade`

Example for switching to a different model:
```yaml
model:
  storageUri: "hf://facebook/opt-350m"
  name: "opt-350m"
  maxModelLen: 2048
```
