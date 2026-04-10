# Sign a Model and Upload to HuggingFace

Step-by-step guide to download a model, sign it with
[sigstore/model-transparency](https://github.com/sigstore/model-transparency),
and upload the signed model to HuggingFace.

## Prerequisites


| Tool                     | Install                              |
| ------------------------ | ------------------------------------ |
| Python 3.10+             | [python.org](https://www.python.org) |
| Git                      | [git-scm.com](https://git-scm.com)   |
| HuggingFace CLI (`hf`)   | `pip3 install huggingface_hub`       |
| OpenSSL (key-based only) | Included on macOS/Linux              |


## Step 1 — Create a Python Virtual Environment

A virtual environment keeps all dependencies isolated from your system Python.
Every subsequent step runs inside this environment.

```bash
python3 -m venv signing-env
source signing-env/bin/activate
```

Your prompt should now show `(signing-env)`. Verify you are inside:

```bash
which python3
# Should print: .../signing-env/bin/python3
```

> **Note:** On macOS, `pip` may not exist but `pip3` does. Inside the venv
> either command works. If you see `zsh: command not found: pip`, use `pip3`.

## Step 2 — Install the HuggingFace CLI

```bash
pip3 install huggingface_hub
```

Verify it is available:

```bash
hf --version
```

Log in (required for uploading):

```bash
hf auth login
```

This prompts for a [HuggingFace access token](https://huggingface.co/settings/tokens).
Create a token with **write** permissions.

## Step 3 — Download the Model

```bash
hf download Qwen/Qwen2.5-0.5B-Instruct --local-dir ./model-files
```

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

## Step 4 — Install Model Signing

Clone the model-transparency repository and install the `model_signing` package:

```bash
git clone https://github.com/sigstore/model-transparency
cd model-transparency
```

Install the `model_signing` module (the venv is already active):

```bash
pip3 install .
```

Verify the install:

```bash
python3 -m model_signing --help
```

## Step 5 — Sign the Model

You have two options: **keyless signing** (Sigstore OIDC) or **key-based signing**.

### Option A — Keyless Signing (Sigstore)

```bash
python3 -m model_signing sign ../model-files
```

This opens a browser for OIDC authentication (Google, GitHub, or Microsoft).
The signing event is recorded in Sigstore's transparency log. The signature
file is written to `../model-files/model.sig` by default.

### Option B — Key-Based Signing (EC P-256)

Generate a key pair:

```bash
openssl ecparam -genkey -name prime256v1 -noout -out signing-key.pem
openssl ec -in signing-key.pem -pubout -out signing-key.pub
```

Sign with the private key:

```bash
python3 -m model_signing sign key \
    --private_key signing-key.pem \
    ../model-files
```

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

## Step 6 — Verify the Signature (Local Check)

### Keyless verification (Sigstore)

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

### Key-based verification

```bash
python3 -m model_signing verify key \
    --signature ../model-files/model.sig \
    --public_key signing-key.pub \
    ../model-files
```

A successful verification prints a confirmation with no errors.

## Step 7 — Upload the Signed Model to HuggingFace

```bash
cd ..
hf upload YOUR_HF_USERNAME/signed-model ./model-files .
```

Verify the upload:

```bash
hf models info YOUR_HF_USERNAME/signed-model
```

This shows detailed metadata for a single model — size, tags, last modified
date, and the list of files (confirm `model.sig` is present).

To list all your models on HuggingFace:

```bash
hf models ls --search "YOUR_HF_USERNAME"
```

This searches across all public models matching your username and returns a
summary list. Useful when you have multiple models and want a quick overview.

You can also visit your model page directly:

```
https://huggingface.co/YOUR_HF_USERNAME/signed-model
```

## Cleaning Up

Deactivate the virtual environment when finished:

```bash
deactivate
```

The `model-transparency/` clone can be removed if no longer needed:

```bash
rm -rf model-transparency
```

## Next Steps

Once the signed model is on HuggingFace, you can package it as an OCI image
for use with the Helm chart and Model Validation Operator. See the
[README](../README.md) for deployment instructions.