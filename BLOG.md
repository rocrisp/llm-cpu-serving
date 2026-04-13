# In-Cluster LLM Inference with Sigstore Model Signing on OpenShift AI

*CPU-based inference for development and prototyping on OpenShift AI*

---

## Introduction

If you already have an OpenShift cluster with OpenShift AI, you can run
an LLM application on CPU without waiting for GPU hardware. CPU inference is
slow and limited to small models, but it lets you build and validate the full
stack (RAG pipeline, model signing, deployment automation) on existing
infrastructure while GPU procurement is in progress.

This guide covers how to deploy an HR policy assistant using
**Qwen2.5-0.5B-Instruct** via vLLM, AnythingLLM for RAG-based chat, and
Sigstore's [Model Validation Operator](https://github.com/sigstore/model-validation-operator)
for model integrity verification. It deploys with a single `helm install`.

What the deployment includes:

- CPU-based LLM inference via KServe on existing worker nodes (slow — expect 20-30s responses)
- No data egress at runtime — once the model is downloaded, all inference runs on-cluster
- RAG chat interface with document upload and source citations
- Cryptographic model signing and verification using Sigstore
- Helm chart that manages everything in one namespace

> **New to some of these topics?** Here are good starting points:
> - **Kubernetes:** [Kubernetes Basics Tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
> - **OpenShift:** [OpenShift Interactive Learning](https://developers.redhat.com/learn)
> - **LLMs and inference:** [Intro to Large Language Models](https://www.youtube.com/watch?v=osKyvYJ3PRM) (Andrej Karpathy)
> - **RAG systems:** [Contextual Retrieval](https://www.anthropic.com/index/contextual-retrieval) (Anthropic)

---

## Why run an LLM on CPU?

An OpenShift cluster with OpenShift AI already has KServe, the operator
framework, OAuth, RBAC, persistent storage, and a container runtime. That's
everything needed to serve an LLM. The only addition is a Helm chart and a
model. The goal is to start building now on what you already have.

GPU inference is 10-20x faster. A response that takes 1-2 seconds on GPU
takes 20-30 seconds on CPU. For **development and prototyping** — building
the application, testing the RAG pipeline, iterating on prompts, validating
the signing workflow — CPU inference lets you move forward without waiting
for GPU procurement or cloud budget approval.

The default model is [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
— 500M parameters, ~1GB on disk, 2-3 tokens/second on CPU with float32.
It works for RAG workloads where the model answers from retrieved document
context, but don't expect strong reasoning or nuanced answers. To switch
models, change `--set model.storageUri` during `helm install`.

| Model | Parameters | CPU Speed |
|-------|-----------|-----------|
| Qwen2.5-0.5B-Instruct | 0.5B | ~2-3 tok/s |
| Qwen2.5-1.5B-Instruct | 1.5B | ~1-2 tok/s |
| Qwen2.5-3B-Instruct | 3B | ~0.5-1 tok/s |

CPU inference is slow (20-30s per response), limited to small models (0.5B-3B),
and does not scale for concurrent users. It is suited for development,
prototyping, data-sovereign environments, and low-traffic internal tools.

---

## What does the architecture look like?

A Helm chart deploys vLLM for inference, AnythingLLM for RAG-based chat, and
the Sigstore Model Validation Operator for model signing — all in one
namespace. Users ask questions through AnythingLLM, which searches uploaded
documents and sends the relevant context to vLLM for a grounded answer.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full component list, request
flow, and container architecture.

---

## What are the security guarantees?

This project addresses two security concerns:

**1. No data egress at runtime.** After the initial model download, the
entire inference pipeline runs on-cluster with zero external calls. No
telemetry, no phone-home, no external API dependency at runtime. Questions,
documents, embeddings, and responses stay within your infrastructure.

This is not an air-gapped cluster — the cluster has internet access and
downloads the model from HuggingFace at pod startup. But once the model is
running, nothing leaves. For environments that require true air-gapping
(no internet at all), the model can be pre-loaded onto a PersistentVolume
or mirrored from an internal registry, eliminating the last external
connection.

**2. Only verified models are served.** Without signing, anyone with write
access to the model repository could modify weights or alter behavior, and
the deployment pipeline would serve it without question. The
[Model Validation Operator](https://github.com/sigstore/model-validation-operator)
blocks any model that hasn't been cryptographically signed and verified. This
is a supply chain problem that requires the same rigor as container image
signing.

Everything that follows — the signing workflow, the deployment steps, the
verification flow — implements these two guarantees.

---

## How does model signing work?

The signing uses [sigstore/model-transparency](https://github.com/sigstore/model-transparency)
with keyless OIDC — no keys to manage, your identity (e.g., GitHub email)
is the signing credential. See the [Signing Guide](docs/SIGNING-GUIDE.md)
for the end-to-end workflow.

---

## How do I get started?

Three steps to go from zero to a running HR assistant:

1. **Sign the model** — Download a model from HuggingFace and sign it with Sigstore (keyless OIDC). See the [Signing Guide](docs/SIGNING-GUIDE.md).

2. **Upload the model** — Push the signed model to your HuggingFace repository (e.g., `hf://YOUR_HF_USERNAME/signed-model`). The signing guide covers this end to end.

3. **Deploy** — Clone the repo and run `helm install` with your model URI and signing identity. See [README.md](README.md) for prerequisites and deployment steps.

```bash
git clone https://github.com/opdev/llm-cpu-serving.git && cd llm-cpu-serving/
oc new-project hr-assistant

helm install hr-assistant helm/ --namespace hr-assistant \
    --set signing.enabled=true \
    --set model.storageUri=hf://YOUR_HF_USERNAME/signed-model \
    --set signing.certificateIdentity="YOUR_EMAIL" \
    --set signing.certificateOidcIssuer="https://github.com/login/oauth"
```

   | Flag | Purpose |
   |------|---------|
   | `signing.enabled=true` | Enables model signature verification via the Model Validation Operator |
   | `model.storageUri` | HuggingFace repo where the signed model is hosted; KServe downloads it at pod startup |
   | `signing.certificateIdentity` | Email address of the person who signed the model (must match the OIDC identity used during signing) |
   | `signing.certificateOidcIssuer` | The OIDC provider used for signing (e.g., GitHub, Google) |

---

## How does verification work?

Once the Helm chart is deployed, the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator)
handles verification without any manual steps. Helm creates a `ModelValidation`
CR that defines the expected signing identity, and labels the predictor pod so
the operator's webhook can find it. The webhook injects a `model-validation`
init container that runs before vLLM starts.

This init container checks every file in `/mnt/models` against the hashes
recorded in `model.sig` and verifies the signing identity matches the
`ModelValidation` CR. If everything checks out, vLLM starts normally. If
anything is wrong — a modified file, a missing signature, a mismatched
identity — the pod stays in `Init:CrashLoopBackOff` and the model is never
served.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the `ModelValidation` CR spec.

---

## What happens if someone tampers with the model?

To see this in action, edit any file in the signed model repo directly on
HuggingFace (e.g., modify `LICENSE`), then delete the predictor pod to force
a re-download:

```bash
oc delete pod -n ${PROJECT} -l serving.kserve.io/inferenceservice
```

The new pod gets stuck in `Init:CrashLoopBackOff`. Check the logs:

```
Verification failed:
Hash mismatches (1):
LICENSE: expected Digest(algorithm..., got Digest(algorithm...
```

The file hash no longer matches what was recorded in `model.sig` at signing
time. Revert the change on HuggingFace and delete the pod again to restore.

---

## What can I build with this?

These are prototyping scenarios — validating the concept before committing to
GPU. The domain knowledge comes from uploaded documents and the system prompt,
not the model. Swap those for a different use case:

| Use Case | Documents | System Prompt Focus |
|----------|-----------|-------------------|
| HR policy assistant | Handbooks, FMLA guides | Regulated HR |
| IT support | Runbooks, architecture docs | Triage procedures |
| Customer support | Product manuals, FAQs | Accurate responses |
| Legal research | Contracts, compliance docs | Flag issues |

---

## What does it cost?

| Approach | Relative cost | Latency | Quality | Data egress | Best for |
|----------|--------------|---------|---------|-------------|----------|
| **Cloud API** (OpenAI, etc.) | Low upfront, ongoing per-use | 1-2s | High (large models) | Yes — data leaves your network | Fastest path to production quality |
| **GPU self-hosted** | High upfront (hardware + power) | 1-2s | High | None at runtime | Production workloads, on-prem requirement |
| **CPU self-hosted** (this project) | Near-zero (existing infra) | 20-30s | Low-medium (small models only) | None at runtime | Development, prototyping, data-sovereign environments |

The cost advantage of CPU is that you're using already-provisioned capacity.
The trade-off: slow responses, small models, and no path to scale. If the
application proves valuable during the CPU prototyping phase, plan for GPU
before going to production. The Helm chart, signing workflow, and RAG
pipeline all transfer.

---

## What if something goes wrong?

| Symptom | Common Cause |
|---------|-------------|
| `Init:CrashLoopBackOff` | Signature mismatch, wrong `certificateIdentity`, missing `model.sig` |
| Pod `Pending` | Unbound PVC or insufficient resources |
| Slow responses (>60s) | Not enough CPUs allocated |
| `ImagePullBackOff` | Registry unreachable or wrong image tag |

See [README.md](README.md) for detailed troubleshooting commands.

---

## References

- **This project:** https://github.com/opdev/llm-cpu-serving
- **Sigstore Model Validation Operator:** https://github.com/sigstore/model-validation-operator
- **Sigstore Model Transparency:** https://github.com/sigstore/model-transparency
- **vLLM:** https://docs.vllm.ai/ | [CPU support](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html)
- **KServe:** https://kserve.github.io/website/
- **AnythingLLM:** https://github.com/Mintplex-Labs/anything-llm
- **Qwen2.5-0.5B-Instruct:** https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct
- **OpenShift AI:** https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai

---

*Questions or feedback? Open an issue on
[GitHub](https://github.com/opdev/llm-cpu-serving/issues).*
