# Sign a Model and Upload to HuggingFace

Step-by-step guide to download a model, **keyless sign** it with
[Sigstore](https://www.sigstore.dev) via
[sigstore/model-transparency](https://github.com/sigstore/model-transparency),
and upload the signed model to HuggingFace. Keyless signing uses your existing
identity (GitHub, Google, or Microsoft) — no keys to generate, store, or rotate.

## Prerequisites

| Tool                     | Install                                |
| ------------------------ | -------------------------------------- |
| Python 3.10+             | [python.org](https://www.python.org)   |
| Git + Git LFS            | [git-scm.com](https://git-scm.com), [git-lfs.com](https://git-lfs.com) |
| HuggingFace account      | [huggingface.co/join](https://huggingface.co/join) |
| HuggingFace access token | [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) — create with **write** permissions |

## Step 1 — Download the Model

Clone the model repository from HuggingFace using Git:

```bash
git lfs install
git clone https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct ./model-files
```

> **Note:** `git lfs install` is required once per machine so that Git LFS
> handles the large model files (e.g. `.safetensors`). If you don't have Git LFS,
> install it from [git-lfs.com](https://git-lfs.com).

Remove git metadata (not part of the model):

```bash
rm -rf ./model-files/.git ./model-files/.gitattributes
```

Verify the download:

```bash
ls -lh ./model-files/
```

Expected files include `config.json`, `model.safetensors`, `tokenizer.json`,
`tokenizer_config.json`, and others.

> For other download methods (Python API, `hf download` CLI, faster Xet-based
> downloads), see the
> [HuggingFace downloading guide](https://huggingface.co/docs/hub/models-downloading#using-git).

## Step 2 — Install Model Signing

Clone the model-transparency repository, create a Python virtual environment
inside it, and install the `model_signing` package:

```bash
git clone https://github.com/sigstore/model-transparency
cd model-transparency
python3 -m venv venv
source venv/bin/activate
pip3 install .
```

Verify the install:

```bash
python3 -m model_signing --help
```

## Step 3 — Sign the Model (Keyless)

```bash
python3 -m model_signing sign sigstore --signature ../model-files/model.sig ../model-files
```

This opens a browser for OIDC authentication (Google, GitHub, or Microsoft).
No private keys are involved — your identity is verified through your provider
and the signing event is recorded in Sigstore's public transparency log. The
`--signature` flag places the signature file inside the model directory so it
gets uploaded alongside the model files.

> **Note:** Key-based signing (EC P-256) is also supported. See the
> [model-transparency documentation](https://github.com/sigstore/model-transparency#signing)
> for details.

### Confirm the signature was created

```bash
ls -la ../model-files/model.sig
```

You should see a file like:

```
-rw-r--r--  1 user  staff  6367  ... model.sig
```

If `model.sig` is missing, the signing step did not complete successfully.
Re-run the sign command above.

## Step 4 — Verify the Signature (Local Check)

```bash
python3 -m model_signing verify sigstore \
    --signature ../model-files/model.sig \
    --identity "<your-email>" \
    --identity-provider "https://github.com/login/oauth" \
    ../model-files
```

Replace `--identity` with the email used during the OIDC signing flow.
Other supported providers:

- Google: `--identity-provider "https://accounts.google.com"`
- Microsoft: `--identity-provider "https://login.microsoftonline.com"`

A successful verification prints a confirmation with no errors.

## Step 5 — Upload the Signed Model to HuggingFace

Install the [HuggingFace CLI](https://huggingface.co/docs/huggingface_hub/en/guides/cli) and log in:

```bash
hf auth login
```

This prompts for a [HuggingFace access token](https://huggingface.co/settings/tokens).
Create a token with **write** permissions.

Upload the signed model files:

```bash
cd ..
hf upload YOUR_HF_USERNAME/signed-model ./model-files .
```

Replace `YOUR_HF_USERNAME` with your HuggingFace username. This creates the
repo if it doesn't exist and uploads all files including `model.sig`.

Verify the upload:

```bash
hf models info YOUR_HF_USERNAME/signed-model
```

Confirm that `model.sig` appears in the file list alongside the model files.

## Cleaning Up

Deactivate the virtual environment when finished:

```bash
deactivate
```

The `model-transparency/` directory (which contains the venv) can be removed
if no longer needed:

```bash
rm -rf model-transparency
```
