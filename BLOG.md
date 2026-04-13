# In-Cluster LLM Inference with Sigstore Model Signing on OpenShift AI

*Model integrity is a supply chain problem that requires the same rigor as container image signing.*

---

## What is this?

An HR policy assistant deployed on OpenShift AI using Helm:

- **[Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)** — small LLM served by vLLM on CPU
- **[AnythingLLM](https://github.com/Mintplex-Labs/anything-llm)** — RAG-based chat with document upload and citations
- **[sigstore/model-transparency](https://github.com/sigstore/model-transparency)** — cryptographic model signing
- **[Sigstore Model Validation Operator](https://github.com/sigstore/model-validation-operator)** — model integrity verification at deployment

No data leaves the cluster at runtime — all inference runs in-cluster.

> **New to some of these topics?**
> [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/) |
> [OpenShift Learning](https://developers.redhat.com/learn) |
> [Intro to LLMs](https://www.youtube.com/watch?v=osKyvYJ3PRM) (Karpathy) |
> [RAG Overview](https://www.anthropic.com/index/contextual-retrieval) (Anthropic)

---

## Why run an LLM on CPU?

You don't need a GPU to start. If you have an OpenShift cluster with
OpenShift AI, you can deploy a working RAG assistant on CPU today — sign the
model and deploy with Helm. 

It's slow (20-30s per response), but it's functional. 

When GPU hardware is available, the same Helm chart, signing  
workflow, and RAG pipeline carry over.

---

## What does the architecture look like?

The architecture has two parts: signing and serving.

**Signing** happens before deployment. You download a model, sign its files  
with [sigstore/model-transparency](https://github.com/sigstore/model-transparency) (which produces a `model.sig` file), and upload the signed model to  
HuggingFace.

**Serving** is handled by a Helm chart that deploys vLLM for inference,  
AnythingLLM for RAG-based chat, and the [Model Validation Operator](https://github.com/sigstore/model-validation-operator) for verification.

Before the model is served, KServe downloads it, the operator
verifies it against `model.sig`, and only then does inference begin.

Users ask questions through AnythingLLM, which searches uploaded documents and sends  
the relevant context to vLLM for a grounded answer.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full component list, request
flow, and container architecture.

---

## What are the security guarantees?

This project addresses two security concerns:

**1. No data leaves the cluster while the model is running.** After the initial model download, the  
entire inference pipeline runs in-cluster with zero external calls. No  
telemetry, no phone-home, no external API dependency at runtime. Questions,  
documents, embeddings, and responses stay within your infrastructure.

This is not an air-gapped cluster — the cluster has internet access and  
downloads the model from HuggingFace during deployment. But once the model is
running, nothing leaves. For environments that require true air-gapping  
(no internet at all), the model can be pre-loaded onto a PersistentVolume  
or served from an internal storage endpoint, eliminating the last external  
connection.

**2. Only verified models are served.** Without signing, anyone with write
access to the model repository could modify weights or alter behavior, and
the deployment pipeline would serve it without question. 

The [Model Validation Operator](https://github.com/sigstore/model-validation-operator) blocks any model that hasn't been cryptographically signed and verified.

---

## How does model signing work?

The signing uses [sigstore/model-transparency](https://github.com/sigstore/model-transparency)
with keyless OIDC — no keys to manage, your identity (e.g., GitHub email)
is the signing credential. See the [Signing Guide](docs/SIGNING-GUIDE.md)
for the end-to-end workflow.

---

## How do I get started?

Two steps to go from zero to a running HR assistant:

1. **Download, sign, and upload the model** — Download a model from HuggingFace, sign it with Sigstore (keyless OIDC), and push it to your HuggingFace repository. See the [Signing Guide](docs/SIGNING-GUIDE.md).
2. **Deploy** — Clone the repo and run `helm install` with your model URI and signing identity. See [README.md](README.md) for prerequisites and deployment steps.

---

## How does verification work?

Once the Helm chart is deployed, the
[Model Validation Operator](https://github.com/sigstore/model-validation-operator) handles verification automatically. 

**Here's what happens:**

1. Helm creates a `ModelValidation` CR with the expected signing identity
2. Helm labels the predictor pod with ${\color{green}\texttt{validation.ml.sigstore.dev/ml}}$ so the operator's webhook can find it
3. The webhook injects a `model-validation` init container that runs before the model is served
4. The init container verifies every file in `/mnt/models` against the hashes in `model.sig`
5. It confirms the signing identity matches the `ModelValidation` CR

If everything checks out, the model is served normally. If anything fails — a modified
file, a missing signature, a mismatched identity — the pod stays in
`Init:CrashLoopBackOff` and the model is never served.

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


| Use Case            | Documents                   | System Prompt Focus |
| ------------------- | --------------------------- | ------------------- |
| HR policy assistant | Handbooks, FMLA guides      | Regulated HR        |
| IT support          | Runbooks, architecture docs | Triage procedures   |
| Customer support    | Product manuals, FAQs       | Accurate responses  |
| Legal research      | Contracts, compliance docs  | Flag issues         |


---

## What does it cost?


| Approach                           | Relative cost                   | Latency | Quality                        | Data egress                    | Best for                                              |
| ---------------------------------- | ------------------------------- | ------- | ------------------------------ | ------------------------------ | ----------------------------------------------------- |
| **Cloud API** (OpenAI, etc.)       | Low upfront, ongoing per-use    | 1-2s    | High (large models)            | Yes — data leaves your network | Fastest path to production quality                    |
| **GPU self-hosted**                | High upfront (hardware + power) | 1-2s    | High                           | None at runtime                | Production workloads, on-prem requirement             |
| **CPU self-hosted** (this project) | Near-zero (existing infra)      | 20-30s  | Low-medium (small models only) | None at runtime                | Development, prototyping, data-sovereign environments |


The cost advantage of CPU is that you're using already-provisioned capacity.
The trade-off: slow responses, small models, and no path to scale. If the
application proves valuable during the CPU prototyping phase, plan for GPU
before going to production. The Helm chart, signing workflow, and RAG
pipeline all carry over to a GPU deployment.

---

## References

- **This project:** [https://github.com/opdev/llm-cpu-serving](https://github.com/opdev/llm-cpu-serving)
- **Sigstore Model Validation Operator:** [https://github.com/sigstore/model-validation-operator](https://github.com/sigstore/model-validation-operator)
- **Sigstore Model Transparency:** [https://github.com/sigstore/model-transparency](https://github.com/sigstore/model-transparency)
- **vLLM:** [https://docs.vllm.ai/](https://docs.vllm.ai/) | [CPU support](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html)
- **KServe:** [https://kserve.github.io/website/](https://kserve.github.io/website/)
- **AnythingLLM:** [https://github.com/Mintplex-Labs/anything-llm](https://github.com/Mintplex-Labs/anything-llm)
- **Qwen2.5-0.5B-Instruct:** [https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
- **OpenShift AI:** [https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)

---

*Questions or feedback? Open an issue on [GitHub](https://github.com/opdev/llm-cpu-serving/issues).*