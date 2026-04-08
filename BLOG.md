# Building Your First AI Assistant: A Beginner's Guide to Running LLMs on CPU with OpenShift

*Learn how to deploy a fully functional AI chatbot without expensive GPUs*

---

## Introduction: AI Without Breaking the Bank

You've probably heard about ChatGPT, Claude, and other AI assistants that seem to understand and respond to human language. These systems use something called **Large Language Models (LLMs)**—sophisticated AI models trained on vast amounts of text to understand and generate human-like responses.

But here's the catch: most tutorials and guides assume you have access to expensive GPU hardware that costs thousands of dollars. What if you want to build and deploy your own AI assistant using just regular CPU-based servers that you already have?

That's exactly what this project does. We're going to build a complete AI-powered HR assistant that runs entirely on CPU—no GPUs required. By the end of this guide, you'll understand:

- What LLMs are and how they work (in simple terms)
- How to deploy your own AI assistant on OpenShift
- How all the pieces fit together to create an intelligent chatbot
- Why this approach is practical and cost-effective

**Real-world scenario:** Imagine you're an HR representative at a bank. You have hundreds of pages of HR policies, compliance documents, and procedures. Instead of searching through documents for hours, wouldn't it be nice to just ask questions like "What do I need to know about giving an employee a raise?" and get instant, accurate answers with citations?

That's what we're building today.

---

## Part 1: Understanding the Basics

### What is a Large Language Model (LLM)?

Think of an LLM as a very sophisticated autocomplete system. You know how your phone predicts the next word when you're texting? An LLM does something similar, but at a much more advanced level.

**Simple analogy:** If you've ever played the game where someone starts a story and others continue it, that's similar to how LLMs work. Given the beginning of a sentence or conversation, the LLM predicts what should come next based on patterns it learned from reading millions of documents during training.

For example:
- **You type:** "The capital of France is..."
- **LLM predicts:** "Paris"

But LLMs can do much more than simple completion. They can:
- Answer questions
- Summarize documents
- Write code
- Have conversations
- Provide advice based on context

### What is "Inference"?

**Inference** is just a fancy word for "using the model to make predictions."

Think of it like this:
- **Training** = Teaching a student by having them study textbooks
- **Inference** = The student taking a test and using what they learned

When you ask an LLM a question, the process of generating an answer is called "inference." The model isn't learning anything new—it's using what it already knows to respond.

### Why CPU Instead of GPU?

**GPUs (Graphics Processing Units)** are specialized chips originally designed for rendering video games and graphics. They happen to be excellent at the mathematical operations that AI models need, so most AI systems use them.

**CPUs (Central Processing Units)** are the regular processors in every computer. They're more general-purpose but slower for AI tasks.

**So why use CPUs?**

1. **Cost:** GPUs designed for AI cost $10,000-$50,000+ each. CPUs are standard equipment.
2. **Availability:** You probably already have CPU-based servers in your organization.
3. **Good enough:** For many use cases, especially with smaller models, CPU inference is perfectly adequate.

**The trade-off:**
- GPU: Answers in 1-2 seconds
- CPU: Answers in 20-30 seconds

For an internal HR assistant where someone asks a question every few minutes, that 20-30 second wait is perfectly acceptable—and saves you tens of thousands of dollars.

---

## Part 2: Meet Qwen2.5-0.5B-Instruct - Your AI Brain

### What Model Are We Using?

We're using **Qwen2.5-0.5B-Instruct**, a language model created by Alibaba's Qwen team. The "0.5B" means it has 500 million parameters. The "Instruct" suffix means it has been fine-tuned to follow instructions and hold conversations.

**What are parameters?**
Think of parameters as the model's "knowledge neurons." More parameters = more knowledge and capability, but also more computing power needed.

**Size comparison:**
- **Qwen2.5-0.5B:** 500 million parameters (what we're using)
- **GPT-3:** 175 billion parameters (350x larger!)
- **ChatGPT-4:** Estimated 1.7 trillion parameters (3,400x larger!)

**Why such a small model?**

Because for focused tasks (like answering HR questions from a specific set of documents), you don't need the world's most powerful AI. Qwen2.5-0.5B-Instruct is:
- **Fast** on CPUs (2-3 tokens/second)
- **Small** (~1GB on disk)
- **Effective** for question-answering and instruction-following tasks
- **Free** and open-source
- **Has a built-in chat template** (no external template needed)

It's like using a calculator instead of a supercomputer to add 2+2. The calculator is perfectly adequate for the task.

---

## Part 3: The Technology Stack Explained

Let's break down all the technologies involved, starting from the simplest concepts.

### 🏗️ Kubernetes and OpenShift

**Kubernetes** (often abbreviated as "K8s") is like a smart traffic controller for your applications. Imagine you have multiple applications that need to run on multiple servers. Kubernetes automatically:
- Decides which server runs which application
- Restarts applications if they crash
- Distributes incoming requests
- Manages resources (CPU, memory, storage)

**OpenShift** is Red Hat's enterprise version of Kubernetes with extra features like:
- Better security
- Built-in monitoring
- Developer-friendly tools
- Enterprise support

**Think of it this way:**
- **Kubernetes** = Android (open-source operating system)
- **OpenShift** = Samsung Galaxy phone (Android + extra features)

### 🤖 vLLM - The Inference Engine

**vLLM** is the software that actually runs the LLM and generates responses. It's optimized to:
- Load the model into memory
- Process your questions
- Generate responses quickly
- Handle multiple requests

**Analogy:** If the LLM is a recipe book, vLLM is the chef who reads the recipes and cooks the food.

### 💬 AnythingLLM - The User Interface

**AnythingLLM** is the chat interface where users actually interact with the AI. It provides:
- A clean web interface for conversations
- Document uploading and processing
- Chat history
- Different workspaces for different topics

**Analogy:** If vLLM is the engine of a car, AnythingLLM is the dashboard, steering wheel, and controls that let you drive it.

### 📚 RAG - Making Your AI Smart About Your Documents

**RAG** stands for **Retrieval-Augmented Generation**. This is a crucial concept that makes your AI assistant actually useful for specific tasks.

**The problem:** Qwen2.5-0.5B was trained on general internet text. It doesn't know about *your* company's HR policies, *your* procedures, or *your* documents.

**The solution:** RAG combines two steps:

1. **Retrieval:** When you ask a question, the system searches through your documents to find relevant information.
2. **Generation:** The AI uses that retrieved information to generate an answer.

**Step-by-step example:**

Let's say you ask: *"What's our policy on remote work?"*

1. **Your question** is converted into numbers (embeddings) that represent its meaning
2. **The system searches** your uploaded documents for sections about remote work
3. **It finds** the relevant policy sections
4. **These sections** are sent to the LLM along with your question
5. **The LLM generates** an answer based on the actual policy documents
6. **You receive** an accurate answer with citations to the source documents

**Without RAG:** The AI would make up an answer based on general knowledge about remote work.
**With RAG:** The AI answers based on your actual company policies.

**Analogy:** Imagine taking an open-book test versus a closed-book test. RAG gives the AI access to the "textbook" (your documents) when answering questions.

### 🔍 Vector Database and Embeddings

This is where it gets a bit technical, but I'll make it simple.

**Embeddings** are a way to convert text into numbers that represent meaning.

**Example:**
- The word "king" might become: [0.2, 0.5, 0.1, 0.8, ...]
- The word "queen" might become: [0.2, 0.5, 0.1, 0.7, ...]
- Notice they're similar because the words have similar meanings

**Vector Database** stores these number representations so you can search for "similar" meanings.

**In our system:**
1. All your HR documents are converted to embeddings
2. Stored in LanceDB (the vector database)
3. When you ask a question, it's also converted to embeddings
4. The system finds documents with similar embeddings (similar meaning)
5. Those documents are used to answer your question

**Analogy:** Instead of searching for exact word matches (like Ctrl+F), embeddings let you search for similar *meanings*. If you search for "vacation policy," it will also find documents about "paid time off" and "leave procedures" because they mean similar things.

---

## Part 4: How It All Works Together

Now let's see how all these pieces connect when you ask a question.

### The Complete Journey of a Question

Let's trace what happens when you ask: *"What do I need to know about giving an employee a raise?"*

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. YOU TYPE YOUR QUESTION                    │
│                 "What about giving a raise?"                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              2. ANYTHINGLLM RECEIVES YOUR MESSAGE               │
│                                                                 │
│  The chat interface receives your question and begins           │
│  processing it. First, it needs to find relevant context.       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│           3. CONVERT QUESTION TO EMBEDDING (NUMBERS)            │
│                                                                 │
│  Your question is converted to a numerical representation:      │
│  "What about giving a raise?" → [0.1, 0.7, 0.2, 0.9, ...]      │
│                                                                 │
│  This uses a special embedding model that understands meaning.  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│          4. SEARCH VECTOR DATABASE FOR SIMILAR CONTENT          │
│                                                                 │
│  The system searches LanceDB for documents with similar         │
│  embeddings (similar meaning). It finds:                        │
│                                                                 │
│  📄 "Compensation_Policy.pdf" - Section 3.2                     │
│  📄 "HR_Procedures.pdf" - Salary Adjustment Process             │
│  📄 "Compliance_Guide.pdf" - Pay Equity Requirements            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              5. CONSTRUCT THE FULL PROMPT FOR LLM               │
│                                                                 │
│  AnythingLLM creates a detailed prompt with context:            │
│                                                                 │
│  System: You are an HR assistant. Use the following docs       │
│  to answer questions.                                           │
│                                                                 │
│  Context:                                                       │
│  [Text from Compensation_Policy.pdf Section 3.2]                │
│  [Text from HR_Procedures.pdf - Salary Adjustment]              │
│  [Text from Compliance_Guide.pdf - Pay Equity]                  │
│                                                                 │
│  User Question: What about giving a raise?                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         6. SEND REQUEST TO VLLM INFERENCE SERVICE               │
│                                                                 │
│  POST http://qwen25-05b-cpu-predictor:8080/v1/chat/completions │
│                                                                 │
│  {                                                              │
│    "model": "qwen25-05b",                                         │
│    "messages": [                                                │
│      {"role": "system", "content": "You are an HR..."},         │
│      {"role": "user", "content": "What about..."}               │
│    ],                                                           │
│    "max_tokens": 512                                            │
│  }                                                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│            7. VLLM LOADS CHAT TEMPLATE AND MODEL                │
│                                                                 │
│  vLLM takes the structured chat and converts it to a format     │
│  the model understands using the chat template:                 │
│                                                                 │
│  "You are an HR assistant...\n\n                                │
│   Context: [policy text]\n\n                                    │
│   What about giving a raise?"                                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                 8. MODEL GENERATES RESPONSE                     │
│                                                                 │
│  Qwen2.5-0.5B processes the prompt token by token on CPU:           │
│                                                                 │
│  Token 1: "When" (0.5 seconds)                                  │
│  Token 2: "considering" (1.0 seconds)                           │
│  Token 3: "a" (1.5 seconds)                                     │
│  Token 4: "salary" (2.0 seconds)                                │
│  ... continues for ~50-100 tokens                               │
│                                                                 │
│  Total time: ~20-25 seconds                                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│               9. VLLM RETURNS COMPLETE RESPONSE                 │
│                                                                 │
│  {                                                              │
│    "choices": [{                                                │
│      "message": {                                               │
│        "content": "When considering a salary raise for an       │
│        employee, you need to keep several key factors in        │
│        mind:\n\n1. Budget approval from finance...\n2.         │
│        Pay equity analysis...\n3. Compliance requirements..."   │
│      }                                                          │
│    }]                                                           │
│  }                                                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         10. ANYTHINGLLM FORMATS WITH CITATIONS                  │
│                                                                 │
│  AnythingLLM adds source citations and displays:                │
│                                                                 │
│  "When considering a salary raise for an employee, you          │
│  need to keep several key factors in mind:                      │
│                                                                 │
│  1. Budget approval from finance department                     │
│  2. Pay equity analysis to ensure fairness                      │
│  3. Compliance with compensation regulations                    │
│  4. Documentation of performance justification                  │
│                                                                 │
│  Sources:                                                       │
│  📄 Compensation_Policy.pdf (p. 12)                             │
│  📄 HR_Procedures.pdf (p. 5-6)"                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   11. YOU SEE THE ANSWER!                       │
│                                                                 │
│  The complete answer appears in your chat interface with        │
│  citations to source documents.                                 │
│                                                                 │
│  Total time: ~25-30 seconds from question to answer             │
└─────────────────────────────────────────────────────────────────┘
```

### What's Happening Behind the Scenes (Technical Details)

For those curious about the technical implementation:

**Kubernetes Resources Created:**

1. **Namespace:** `hr-assistant` - Isolated environment for all components
2. **StatefulSet:** `anythingllm` - Runs the chat interface with persistent storage
3. **Deployment:** `qwen25-05b-cpu-predictor` - Runs the vLLM inference engine
4. **Services:** Network endpoints for communication between components
5. **ConfigMaps:** Configuration files (chat template, trusted CAs)
6. **Secrets:** Sensitive configuration (API keys, OAuth tokens)
7. **PersistentVolumeClaim:** Storage for chat history and uploaded documents

**Container Architecture:**

The `anythingllm` pod has 3 containers:
- **kube-rbac-proxy:** Handles authentication (auto-injected by OpenShift AI controller)
- **anythingllm:** Main chat interface
- **anythingllm-automation:** Database management sidecar

The `qwen25-05b-cpu-predictor` pod has 2-3 containers:
- **model-validation (init container):** Verifies model signature before serving
- **agent:** KServe agent for model lifecycle
- **kserve-container:** vLLM runtime with the model

---

## Part 5: Why This Architecture Works

### Design Decisions Explained

**1. Why KServe for Model Serving?**

KServe is a Kubernetes-native platform for serving ML models. It handles:
- Automatic scaling based on traffic
- Health checks and recovery
- Canary deployments
- Metrics and monitoring

**Benefit:** If the model crashes, KServe automatically restarts it. If traffic increases, it can scale up.

**2. Why Headless Service?**

The service `qwen25-05b-cpu-predictor` is "headless" (ClusterIP: None), which means it connects directly to pod IPs rather than using a load balancer.

**Benefit:** With a single pod, this is more efficient and reduces latency.

**3. Why ConfigMap for Chat Template?**

The chat template is mounted as a ConfigMap volume so you can update it without rebuilding the container image.

**Benefit:** Easy to modify the prompt format for different models or use cases.

**4. Why Separate Embedding and LLM?**

AnythingLLM uses a small local embedding model (all-MiniLM-L6-v2) for document search, separate from the Qwen2.5-0.5B model for generation.

**Benefit:** Embeddings are fast and can run locally. You don't need to call the LLM for every search.

**5. Why float32 Instead of float16?**

On GPUs, using float16 (half precision) saves memory and speeds up computation. On CPUs, float32 is more stable.

**Benefit:** Prevents crashes and numerical instability on CPU.

---

## Part 6: Getting Started - Step by Step

Let's actually deploy this system. I'll explain each step in detail.

### Prerequisites

Before you begin, you need:

1. **OpenShift Cluster** (version 4.16.24+)
   - Can be on-premise, cloud (AWS, Azure, GCP), or local (CRC)
   - At least 8 CPU cores and 8GB RAM available

2. **OpenShift AI** (version 2.16.2+)
   - Installed on your cluster
   - With Single-model serving enabled (KServe)

3. **Command Line Tools**
   - `oc` - OpenShift CLI
   - `helm` - Helm package manager
   - `git` - Version control

4. **User Access**
   - Standard user permissions (no cluster admin needed)
   - Ability to create projects

**Don't have OpenShift?**
- Try OpenShift Local (CRC) for development: https://developers.redhat.com/products/openshift-local/overview
- Get a Developer Sandbox (free): https://developers.redhat.com/developer-sandbox

### Step 1: Clone the Repository

Open your terminal and run:

```bash
git clone https://github.com/rocrisp/llm-cpu-serving.git
cd llm-cpu-serving/
```

**What you're downloading:**
- Helm charts (deployment configuration)
- Kubernetes resource definitions
- Chat template
- Documentation

### Step 2: Create a Project (Namespace)

In OpenShift, a "project" is a namespace where your application will run.

```bash
PROJECT="hr-assistant"
oc new-project ${PROJECT}
```

**What this does:**
- Creates an isolated environment for your app
- Sets up default network policies
- Assigns resource quotas (if configured)

**Expected output:**
```
Now using project "hr-assistant" on server "https://api.cluster.example.com:6443".
```

### Step 3: Deploy with Helm

Helm is a package manager for Kubernetes. Think of it like `apt` or `yum` but for Kubernetes applications.

```bash
helm install ${PROJECT} helm/ --namespace ${PROJECT}
```

**What this command does:**

1. **Reads** the Helm chart from the `helm/` directory
2. **Processes** templates with values from `values.yaml`
3. **Creates** all Kubernetes resources:
   - ConfigMaps
   - Secrets
   - StatefulSets
   - Deployments
   - Services
   - InferenceServices

4. **Waits** for resources to be created (doesn't wait for them to be ready)

**Expected output:**
```
NAME: hr-assistant
LAST DEPLOYED: Fri Mar 13 10:00:00 2026
NAMESPACE: hr-assistant
STATUS: deployed
REVISION: 1
```

### Step 4: Watch the Deployment

Now watch as Kubernetes brings up your application:

```bash
oc -n ${PROJECT} get pods -w
```

The `-w` flag means "watch" - the command will continuously update.

**What you'll see:**

```
NAME                                      READY   STATUS              RESTARTS   AGE
anythingllm-0                             0/2     ContainerCreating   0          10s
anythingllm-seed-xxxxx                    0/1     ContainerCreating   0          10s
qwen25-05b-cpu-predictor-xxxxxxxxx-xxxxx  0/2     Init:0/1            0          10s
```

**Status explanations:**

- **ContainerCreating:** Kubernetes is pulling container images and starting containers
- **Init:0/1:** Running initialization containers (the modelcar-init container that downloads the model)
- **0/2 Running:** Container started but not yet passing health checks
- **1/2 Running:** Some containers ready, others still starting
- **2/2 Running:** All containers ready! ✅

**Timeline:**

- **0-30 seconds:** Containers starting
- **30-90 seconds:** Model downloading from HuggingFace (~500MB)
- **90-120 seconds:** Model loading into memory
- **120+ seconds:** vLLM server ready and accepting requests

**Final expected state:**
```
NAME                                      READY   STATUS      RESTARTS   AGE
anythingllm-0                             2/2     Running     0          3m
anythingllm-seed-xxxxx                    0/1     Completed   0          3m
qwen25-05b-cpu-predictor-xxxxxxxxx-xxxxx  2/2     Running     0          3m
```

Press `Ctrl+C` to stop watching.

### Step 5: Access the Application

Now let's access the chat interface!

**Option 1: Through OpenShift AI Dashboard**

1. Get your dashboard URL:
   ```bash
   oc get routes rhods-dashboard -n redhat-ods-applications
   ```

2. Open that URL in your browser

3. Navigate to: **Data Science Projects** → **hr-assistant**

4. In the Workbenches section, click **Open** next to AnythingLLM

5. You'll be redirected to the AnythingLLM interface

6. Click on the **Assistant to the HR Representative** workspace

**Option 2: Direct Route (if configured)**

```bash
oc get route anythingllm -n ${PROJECT}
```

### Step 6: Try It Out!

Once in the AnythingLLM interface, try asking:

**Question 1: Simple Test**
```
Hello! Can you help me with HR questions?
```

Expected: The assistant introduces itself and confirms it can help.

**Question 2: Policy Question**
```
What do I need to know about giving an employee a raise?
```

Expected: A detailed answer with multiple points about:
- Budget approval
- Pay equity
- Documentation requirements
- Compliance considerations
- With citations to source documents

**Question 3: Complex Scenario**
```
An employee is requesting FMLA leave. What are the key steps I need to follow?
```

Expected: Step-by-step guidance on FMLA procedures, compliance requirements, and documentation needs.

### Understanding the Response Time

**Why does it take 20-30 seconds?**

Let's break down where the time goes:

1. **Embedding your question:** ~0.5 seconds
2. **Searching vector database:** ~1 second
3. **Constructing prompt with context:** ~0.5 seconds
4. **vLLM processing:**
   - Loading prompt into model: ~2 seconds
   - Generating tokens: ~15-20 seconds (2-3 tokens/second)
5. **Formatting response:** ~1 second

**Total:** ~20-25 seconds

**Is this slow?**

For comparison:
- **ChatGPT on GPU:** 1-2 seconds
- **This system on CPU:** 20-25 seconds

But remember:
- ChatGPT costs OpenAI millions in GPU infrastructure
- This runs on regular servers you already have
- For an internal tool used occasionally, the wait is acceptable
- You're saving $50,000+ on GPU hardware

---

## Part 7: Understanding the Code

Let's look at the key configuration files so you understand what's happening.

### The Helm Chart Structure

```
helm/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Configuration values
└── templates/
    ├── inferenceservice.yaml          # KServe model serving
    ├── servingruntime.yaml            # vLLM configuration
    ├── workbench.yaml                 # AnythingLLM pod
    ├── anythingllm-secret.yaml        # LLM provider config
    ├── vllm-chat-template-configmap.yaml  # Chat template
    └── ... other resources
```

### Key Configuration: values.yaml

```yaml
model:
  storageUri: "hf://Qwen/Qwen2.5-0.5B-Instruct"  # Where to get the model
  name: "qwen25-05b"                              # Model identifier
  maxModelLen: 2048                      # Maximum context length

images:
  vllmRuntime:
    repository: "quay.io/rh-aiservices-bu/vllm-cpu-openai-ubi9"
    tag: "0.3"
  anythingllm:
    repository: "quay.io/rh-aiservices-bu/anythingllm-workbench"
    tag: "1.9.1"

resources:
  inference:
    requests:
      cpu: "2"      # Minimum CPUs
      memory: "4Gi" # Minimum memory
    limits:
      cpu: "8"      # Maximum CPUs
      memory: "8Gi" # Maximum memory
```

**What this means:**

- **storageUri:** The `hf://` prefix tells vLLM to download from HuggingFace
- **Model name:** Used to generate resource names throughout the deployment
- **Images:** Pre-built container images with vLLM and AnythingLLM
- **Resources:** Kubernetes will allocate between 2-8 CPUs and 4-8GB RAM

### Understanding the ServingRuntime

The ServingRuntime defines how vLLM should run:

```yaml
containers:
  - args:
      - --model
      - Qwen/Qwen2.5-0.5B-Instruct  # Model to load
      - --port
      - "8080"                   # API port
      - --max-model-len
      - "2048"                   # Context length
      - --served-model-name
      - qwen25-05b               # Name for API
      - --dtype
      - float32                  # Use 32-bit floats (CPU optimized)
      - --chat-template
      - /app/chat-template/template.jinja  # Custom template
    env:
      - name: VLLM_CPU_DISABLE_AVX512
        value: "1"               # Disable AVX512 optimizations
      - name: ONEDNN_VERBOSE
        value: "0"               # Quiet logging
```

**Why these settings?**

- **dtype: float32** - CPUs handle 32-bit floats better than 16-bit
- **VLLM_CPU_DISABLE_AVX512** - Prevents crashes with certain CPU optimizations
- **chat-template** - Tells vLLM how to format chat conversations

### The Chat Template

Located in `helm/templates/vllm-chat-template-configmap.yaml`:

```jinja
{%- for message in messages -%}
{%- if message['role'] == 'system' -%}
{{ message['content'] }}

{%- endif -%}
{%- if message['role'] == 'user' -%}
{{ message['content'] }}
{%- endif -%}
{%- if message['role'] == 'assistant' -%}
{{ message['content'] }}
{%- endif -%}
{%- endfor -%}
```

**What this does:**

Takes structured chat messages like:
```json
{
  "messages": [
    {"role": "system", "content": "You are an HR assistant."},
    {"role": "user", "content": "What about raises?"}
  ]
}
```

And converts to plain text:
```
You are an HR assistant.

What about raises?
```

This is a simplified example; Qwen2.5-0.5B-Instruct has a built-in chat template that handles this formatting automatically.

---

## Part 8: Model Signing and Verification

### Why Sign Your Models?

When you deploy an AI model in production, how do you know the model hasn't been tampered with? Someone could modify the model weights to introduce backdoors, bias, or malicious behavior. This is especially important in regulated industries like banking.

**Model signing** uses cryptography to create a digital "seal" on your model. If anyone modifies the model after signing, the seal breaks and verification fails.

### How It Works in This Project

This project integrates with the [Model Validation Operator](https://github.com/sigstore/model-validation-operator) from Sigstore to enforce model verification at deployment time.

```
Developer signs model → Packages as OCI image → Deploys with Helm
                                                       │
                                    ┌──────────────────┘
                                    ▼
                         ┌─────────────────────┐
                         │  model-download Job  │
                         │  Copies model to PVC │
                         └──────────┬──────────┘
                                    │
                                    ▼
                         ┌─────────────────────────────────┐
                         │  Model Validation Operator       │
                         │  Injects init container into pod │
                         └──────────┬──────────────────────┘
                                    │
                                    ▼
                         ┌─────────────────────────────┐
                         │  Init container verifies     │
                         │  signature before pod starts │
                         └──────────┬──────────────────┘
                                    │
                            ┌───────┴───────┐
                            │               │
                        PASS ✓          FAIL ✗
                            │               │
                      Pod starts      Pod blocked
                      and serves      (Init:Error)
```

### Enabling Model Signing

1. **Generate a signing key pair:**
   ```bash
   ./scripts/sign-model.sh keygen
   ```

2. **Sign your model:**
   ```bash
   ./scripts/sign-model.sh sign ./model-files --key signing-key.pem
   ```

3. **Package as OCI image and push:**
   ```bash
   podman build --platform linux/amd64 -t quay.io/yourorg/signed-model:v1 .
   podman push quay.io/yourorg/signed-model:v1
   ```

4. **Configure `values.yaml`:**
   ```yaml
   signing:
     enabled: true
     modelImage: "quay.io/yourorg/signed-model:v1"
     publicKeyData: |
       -----BEGIN PUBLIC KEY-----
       <your public key>
       -----END PUBLIC KEY-----
   ```

5. **Deploy** — the operator automatically verifies the model before the pod can serve traffic.

### What Happens If Verification Fails?

The predictor pod stays in `Init:Error` state and never starts serving. You can check the logs:

```bash
oc logs -l serving.kserve.io/inferenceservice -c model-validation -n hr-assistant
```

This prevents tampered models from ever being served to users.

---

## Part 9: Customization and Advanced Topics

### Uploading Your Own Documents

To make the assistant knowledgeable about your organization:

1. **Access AnythingLLM** workspace
2. Click **Upload Documents** in the sidebar
3. Select your files:
   - PDF documents
   - Word docs (.docx)
   - Text files (.txt)
   - Markdown (.md)

4. Click **Process Documents**

**What happens:**
- AnythingLLM splits documents into chunks
- Each chunk is converted to embeddings
- Embeddings are stored in LanceDB
- Future questions will search these documents

**Best practices:**
- Keep documents focused and relevant
- Remove duplicate or outdated content
- Organize by topic if possible
- Start with 10-20 key documents

### Switching to a Different Model

Want to try a different model? Here's how:

1. **Edit values.yaml:**
   ```yaml
   model:
     storageUri: "hf://Qwen/Qwen2.5-1.5B-Instruct"  # Larger model
     name: "qwen25-15b"
     maxModelLen: 2048
   ```

2. **Upgrade the deployment:**
   ```bash
   helm upgrade ${PROJECT} helm/ --namespace ${PROJECT}
   ```

3. **Wait for new pods** to start

**Model recommendations:**

| Model | Parameters | Speed | Quality | Use Case |
|-------|-----------|-------|---------|----------|
| Qwen/Qwen2.5-0.5B-Instruct | 0.5B | Fastest | Good | Quick answers, demos |
| Qwen/Qwen2.5-1.5B-Instruct | 1.5B | Fast | Better | Production use |
| Qwen/Qwen2.5-3B-Instruct | 3B | Moderate | Best | Complex questions |
| TinyLlama/TinyLlama-1.1B-Chat-v1.0 | 1.1B | Fast | Good | General chat |

### Adjusting Resources

If responses are too slow or you have more CPU available:

1. **Edit values.yaml:**
   ```yaml
   resources:
     inference:
       requests:
         cpu: "4"      # More CPUs = faster
         memory: "8Gi"
       limits:
         cpu: "16"     # Allow up to 16 CPUs
         memory: "16Gi"
   ```

2. **Upgrade:**
   ```bash
   helm upgrade ${PROJECT} helm/ --namespace ${PROJECT}
   ```

**Rule of thumb:**
- Doubling CPUs ≈ 1.5x faster inference
- More memory allows larger models
- Beyond 16 CPUs shows diminishing returns

### Monitoring and Troubleshooting

**Check vLLM logs:**
```bash
oc logs -n ${PROJECT} -l app=isvc.qwen25-05b-cpu-predictor -c kserve-container
```

**Check AnythingLLM logs:**
```bash
oc logs -n ${PROJECT} anythingllm-0 -c anythingllm
```

**Check if vLLM is responding:**
```bash
oc port-forward -n ${PROJECT} svc/qwen25-05b-cpu-predictor 8080:80

# In another terminal:
curl http://localhost:8080/health
```

**Common issues:**

1. **Pod stuck in ContainerCreating**
   - Check: `oc describe pod <pod-name> -n ${PROJECT}`
   - Usually: PVC not binding or image pull issues

2. **vLLM keeps restarting**
   - Check: Resource limits (might need more memory)
   - Check: Logs for out-of-memory errors

3. **Slow responses (>60 seconds)**
   - Increase CPU allocation
   - Check if node has other heavy workloads

4. **Chat returns errors**
   - Verify vLLM is healthy: `oc get inferenceservice -n ${PROJECT}`
   - Check service connectivity

---

## Part 10: Real-World Use Cases

### Use Case 1: HR Policy Assistant (What We Built)

**Problem:** HR representatives spend hours searching through policy documents.

**Solution:** This AI assistant with HR policies uploaded.

**Benefits:**
- Instant answers with citations
- Consistent policy interpretation
- New employees get up to speed faster
- Reduces errors from outdated information

**Example interaction:**
```
Q: "An employee wants to take parental leave. What forms do they need?"

A: "For parental leave under FMLA, the employee needs to complete:

1. FMLA Request Form (Form HR-201)
2. Medical Certification (WH-380-F for family member care)
3. Written notice to their manager (at least 30 days in advance when possible)

Additionally, they should:
- Contact the benefits team to discuss continuation of health insurance
- Review the parental leave policy in the Employee Handbook (Section 7.3)
- Submit a leave plan indicating expected dates

Source: FMLA_Policy_2025.pdf (pages 3-5), Employee_Handbook.pdf (page 112)"
```

### Use Case 2: IT Support Assistant

**Adaptation:** Upload IT documentation, troubleshooting guides, runbooks.

**Example:**
```
Q: "User can't connect to VPN. What should I check first?"

A: "For VPN connectivity issues, follow this troubleshooting sequence:

1. Verify network connectivity:
   - Can user access internet without VPN?
   - Check if corporate firewall is blocking VPN ports (443, 1194)

2. Check VPN client:
   - Is the client software up to date? (Latest version: 3.2.1)
   - Try restarting the VPN service
   - Verify authentication credentials

3. Common fixes:
   - Clear VPN client cache
   - Disable IPv6 temporarily
   - Check for conflicting security software

Source: VPN_Troubleshooting_Guide.pdf, IT_Support_Runbook.pdf"
```

### Use Case 3: Customer Support Knowledge Base

**Adaptation:** Upload product manuals, FAQs, support articles.

**Benefits:**
- Support agents get instant answers
- Consistent responses across team
- New agents trained faster
- Reduce escalations

### Use Case 4: Legal Document Research

**Adaptation:** Upload contracts, legal precedents, compliance documents.

**Note:** Use with caution - always have human legal review!

---

## Part 11: Understanding the Costs

Let's do a cost comparison to understand the value proposition.

### Option 1: Cloud-based LLM API (like OpenAI)

**Costs:**
- ChatGPT API: ~$0.002 per 1K tokens
- Average question + answer: ~500 tokens = $0.001
- 1,000 questions/day × 30 days = 30,000 questions
- Monthly cost: **$30-100/month**

**Plus:**
- Privacy concerns (data sent to third party)
- Internet dependency
- Rate limits
- Compliance issues (especially in regulated industries)

### Option 2: GPU-based Self-hosted

**Hardware costs:**
- NVIDIA A100 GPU: $15,000-20,000
- Server + GPU: $25,000-30,000
- Power: ~350W × 24h × 30 days × $0.12/kWh = $302/month

**Total first year:**
- Hardware: $30,000
- Power: $3,600
- **Total: $33,600**

**Benefits:**
- Fast responses (1-2 seconds)
- Full privacy
- No API limits

### Option 3: CPU-based Self-hosted (This Project)

**Hardware costs:**
- Already have CPU servers: $0 (using existing infrastructure)
- Or new server: $3,000-5,000
- Power: ~150W × 24h × 30 days × $0.12/kWh = $130/month

**Total first year:**
- Hardware: $0-5,000 (usually $0)
- Power: $1,560
- **Total: $1,560 (or $0 if using existing servers)**

**Trade-offs:**
- Slower responses (20-30 seconds vs 1-2 seconds)
- Smaller models (but often sufficient)
- Full privacy
- No API limits

### The Winner: CPU for Internal Tools

For internal tools like HR assistants where:
- Users ask questions occasionally (not thousands per second)
- 20-30 second response time is acceptable
- Privacy is important
- You already have CPU infrastructure

**CPU-based is clearly the most cost-effective option.**

---

## Part 12: Security and Privacy Considerations

### Data Privacy

**Where does your data go?**

With this deployment:
1. **Questions and documents stay local** - never sent to third parties
2. **Model is downloaded once** from HuggingFace (public)
3. **All inference happens on your servers**
4. **Chat history stored in your cluster**

**Benefits:**
- GDPR compliant
- HIPAA compliant (if your infrastructure is)
- SOC 2 compliant
- No data sharing with external AI providers

### Authentication and Authorization

**Out of the box:**
- OAuth proxy authentication (uses OpenShift users)
- RBAC integration (only users with project access can use it)
- TLS encryption for web traffic

**To enhance security:**

1. **Limit project access:**
   ```bash
   oc adm policy remove-role-from-group view system:authenticated -n ${PROJECT}
   oc adm policy add-role-to-user view <username> -n ${PROJECT}
   ```

2. **Enable audit logging:**
   - Configure OpenShift audit policies
   - Monitor who accesses the assistant

3. **Implement usage quotas:**
   ```yaml
   # In values.yaml or ResourceQuota
   resources:
     inference:
       limits:
         cpu: "8"
         memory: "8Gi"
   ```

### Compliance Considerations

**For regulated industries (banking, healthcare, etc.):**

✅ **Advantages:**
- All data stays in your infrastructure
- You control the model and data
- Can implement required audit logging
- No third-party data processors

⚠️ **Considerations:**
- Document the AI's role (assistant, not decision-maker)
- Implement human review for critical decisions
- Keep audit logs of questions and responses
- Regular review of responses for accuracy

---

## Part 13: What's Next?

### Level Up Your Deployment

**Beginner:**
- ✅ Deploy the basic system (you just did this!)
- ✅ Upload your documents
- ✅ Try different questions

**Intermediate:**
- 📚 Try different models (opt-350m, opt-1.3b)
- 🎨 Customize the system prompt in the workspace
- 📊 Add monitoring with Prometheus/Grafana
- 🔄 Set up backups for AnythingLLM PVC

**Advanced:**
- 🚀 Implement auto-scaling based on load
- 🔍 Add custom RAG strategies (re-ranking, hybrid search)
- 🧪 Fine-tune a model on your specific documents
- 🏗️ Deploy multiple specialized assistants (HR, IT, Legal, etc.)

### Learning Resources

**Understanding LLMs:**
- [Introduction to Large Language Models](https://www.youtube.com/watch?v=osKyvYJ3PRM) (Andrej Karpathy)
- [Hugging Face NLP Course](https://huggingface.co/learn/nlp-course/chapter1/1)

**OpenShift and Kubernetes:**
- [OpenShift Interactive Learning](https://developers.redhat.com/learn)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)

**RAG Systems:**
- [RAG Explained](https://www.anthropic.com/index/contextual-retrieval) (Anthropic)
- [LangChain Documentation](https://python.langchain.com/docs/get_started/introduction)

**vLLM:**
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM CPU Support](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html)

### Join the Community

- **GitHub Issues:** [Report bugs or request features](https://github.com/rocrisp/llm-cpu-serving/issues)
- **OpenShift AI Community:** [Red Hat Community](https://www.redhat.com/en/blog/products)
- **vLLM Discord:** Community support for vLLM

---

## Part 14: Frequently Asked Questions

### General Questions

**Q: Do I really not need a GPU?**

A: Correct! This entire system runs on CPU. It's slower than GPU (20-30 seconds vs 1-2 seconds), but for many use cases, that's perfectly acceptable. You're trading speed for massive cost savings.

**Q: Can I use this in production?**

A: Yes, with considerations:
- For internal tools with moderate usage: absolutely
- For high-traffic public APIs: probably want GPUs
- For critical systems: add redundancy and monitoring
- Always test with your expected load

**Q: How many users can this support?**

A: With the default configuration (1 pod):
- **Concurrent users:** 1-2 (CPU can only process one request at a time efficiently)
- **Total users:** Unlimited (they just wait in queue)
- **Throughput:** ~2-3 questions per minute

To support more concurrent users, deploy multiple pods or use GPUs.

**Q: Is this enterprise-ready?**

A: The components are:
- vLLM: used by major companies
- KServe: CNCF project, enterprise-grade
- OpenShift: enterprise Kubernetes platform

But you should add:
- Monitoring and alerting
- Backup and disaster recovery
- High availability (multiple pods)
- Resource quotas and limits

### Technical Questions

**Q: Why Qwen2.5-0.5B instead of larger models?**

A:
- **Speed:** Larger models are slower on CPU
- **Memory:** 0.5B fits easily in 4-8GB
- **Quality:** For RAG with good documents, smaller instruction-tuned models work well
- **Built-in chat template:** No external template configuration needed
- **Cost:** Less compute = lower costs

You can easily switch to larger models (Qwen2.5-1.5B, Qwen2.5-3B) if needed.

**Q: Can I fine-tune the model on my data?**

A: Yes, but it's advanced:
1. Export your documents as training data
2. Use tools like [Axolotl](https://github.com/OpenAccess-AI-Collective/axolotl) for fine-tuning
3. Upload the fine-tuned model to HuggingFace
4. Update `values.yaml` to use your model

For most cases, RAG (what we're doing) is simpler and works just as well.

**Q: What if my documents are too large?**

A: Current limits:
- Model context: 2048 tokens (~1500 words)
- Vector DB: No practical limit

If documents are large:
- AnythingLLM automatically chunks them
- Only relevant chunks are sent to the model
- Increase `maxModelLen` if needed

**Q: Can this work offline?**

A: Almost:
- After initial model download: yes, fully offline
- First deployment: needs internet to download model from HuggingFace (~500MB)

To make it truly offline:
- Pre-download model and push to internal registry
- Update `storageUri` to point to internal location

**Q: How do I backup the system?**

A: Key things to backup:

1. **AnythingLLM data:**
   ```bash
   oc get pvc anythingllm -n ${PROJECT}
   # Backup the persistent volume
   ```

2. **Configuration:**
   ```bash
   helm get values ${PROJECT} -n ${PROJECT} > backup-values.yaml
   ```

3. **Uploaded documents:**
   - Stored in AnythingLLM PVC
   - Backup via volume snapshots

### Troubleshooting Questions

**Q: The model is very slow, what can I do?**

Solutions:
1. **Increase CPU allocation** in `values.yaml`
2. **Switch to a smaller model** (Qwen2.5-0.5B is already small)
3. **Reduce max_tokens** in responses
4. **Use faster hardware** (newer Intel CPUs with AVX512)

**Q: Responses don't make sense**

Possible causes:
1. **Model hallucinating:** Add more relevant documents
2. **Poor retrieval:** Check if right documents are being found
3. **Bad prompt:** Adjust system prompt in workspace settings
4. **Model too small:** Try opt-350m or opt-1.3b

**Q: I get "Error: 400 status code (no body)"**

This was a common issue we fixed. Ensure:
1. Chat template ConfigMap is mounted
2. vLLM has `--chat-template` argument
3. Secret has correct provider (generic-openai)

If still broken:
```bash
oc logs -n ${PROJECT} -l app=isvc.qwen25-05b-cpu-predictor
```

**Q: Pod won't start - ImagePullBackOff**

Check:
```bash
oc describe pod <pod-name> -n ${PROJECT}
```

Usually means:
- No internet access to pull images
- Wrong image repository
- Registry authentication needed

---

## Conclusion: You Did It! 🎉

Congratulations! You now understand:

✅ **What LLMs are** and how they work
✅ **What inference means** and why CPU can work
✅ **How RAG enhances** AI with your documents
✅ **The complete architecture** of a production AI system
✅ **How to deploy** and customize your own AI assistant
✅ **Cost comparisons** and when to use CPU vs GPU
✅ **Security and compliance** considerations

### The Big Picture

You've deployed a sophisticated AI system that:
- Runs on regular hardware (no GPUs needed)
- Keeps your data private
- Provides intelligent answers from your documents
- Costs a fraction of cloud AI services
- Is production-ready with proper setup

**Most importantly:** You didn't just copy-paste commands. You understand *why* each component exists and *how* they work together.

### Your Next Steps

1. **Experiment:** Try different models, upload different documents
2. **Customize:** Adjust prompts, tweak settings, optimize for your use case
3. **Share:** Help others in your organization benefit from AI
4. **Learn:** Dive deeper into the topics that interest you
5. **Contribute:** Share your improvements with the community

### One Final Thought

AI doesn't have to be complex or expensive. With the right architecture and understanding, you can build powerful AI tools using resources you already have.

The future of AI isn't just large corporations with massive GPU clusters. It's also teams like yours, running practical AI systems on practical hardware, solving real business problems.

**Now go build something amazing!** 🚀

---

## Appendix: Quick Reference

### Essential Commands

```bash
# Check deployment status
oc get pods -n hr-assistant

# View vLLM logs
oc logs -l app=isvc.qwen25-05b-cpu-predictor -c kserve-container -n hr-assistant

# View AnythingLLM logs
oc logs anythingllm-0 -c anythingllm -n hr-assistant

# Restart a component
oc delete pod anythingllm-0 -n hr-assistant  # Auto-recreates

# Update configuration
helm upgrade hr-assistant helm/ --namespace hr-assistant

# Test API directly
oc port-forward svc/qwen25-05b-cpu-predictor 8080:80 -n hr-assistant
curl http://localhost:8080/v1/models

# Delete everything
helm uninstall hr-assistant --namespace hr-assistant
```

### Resource Links

- **This Project:** https://github.com/rocrisp/llm-cpu-serving
- **Original Project:** https://github.com/rh-ai-quickstart/llm-cpu-serving
- **OpenShift AI:** https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai
- **vLLM:** https://docs.vllm.ai/
- **AnythingLLM:** https://github.com/Mintplex-Labs/anything-llm
- **Qwen Models:** https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct

### Glossary

- **LLM:** Large Language Model - AI trained on text
- **Inference:** Using the model to make predictions
- **RAG:** Retrieval-Augmented Generation - combining search with generation
- **Embedding:** Converting text to numerical vectors
- **Token:** Smallest unit of text (roughly ¾ of a word)
- **KServe:** Kubernetes-based model serving platform
- **Helm:** Kubernetes package manager
- **StatefulSet:** Kubernetes resource for stateful applications
- **ConfigMap:** Kubernetes configuration storage
- **PVC:** PersistentVolumeClaim - storage request

---

*Written with ❤️ for the AI and OpenShift community*

*Questions? Open an issue on [GitHub](https://github.com/rocrisp/llm-cpu-serving/issues)*
