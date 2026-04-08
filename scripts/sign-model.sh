#!/bin/bash
# Sign and verify model files using sigstore model-signing.
#
# The Helm chart integrates with the Model Validation Operator
# (https://github.com/sigstore/model-validation-operator) to enforce
# cryptographic model verification via an init container injected by webhook.
# This script produces the signed model that the operator validates.
#
# Prerequisites:
#   - pip install model-signing   (https://github.com/sigstore/model-transparency)
#   - For key-based signing: openssl (for key generation)
#   - For archive/OCI packaging: tar, podman or docker
#
# Usage:
#   ./scripts/sign-model.sh <action> [options]
#
# Actions:
#   keygen                        Generate an EC P-256 signing key pair
#   sign     <model-dir> [--key <private-key>]
#                                 Sign model files (produces model.sig)
#   verify   <model-dir> [--key <public-key>]
#                                 Verify model signature
#   archive  <model-dir> <output> Create a flat tar.gz of model + signature
#   help                          Show this help
#
# Examples:
#   ./scripts/sign-model.sh keygen
#   ./scripts/sign-model.sh sign ./model-files --key signing-key.pem
#   ./scripts/sign-model.sh verify ./model-files --key signing-key.pub
#   ./scripts/sign-model.sh archive ./model-files signed-model.tar.gz

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || error "'$1' is required but not installed. See: $2"
}

ACTION="${1:-}"
shift || true

case "$ACTION" in

keygen)
    require_cmd openssl "https://www.openssl.org"
    KEY_NAME="${1:-signing-key}"
    info "Generating EC P-256 key pair..."
    openssl ecparam -genkey -name prime256v1 -noout -out "${KEY_NAME}.pem"
    openssl ec -in "${KEY_NAME}.pem" -pubout -out "${KEY_NAME}.pub"
    info "Private key: ${KEY_NAME}.pem"
    info "Public key:  ${KEY_NAME}.pub"
    echo ""
    info "Next steps:"
    echo "  1. Sign:    $0 sign ./model-files --key ${KEY_NAME}.pem"
    echo "  2. Add the public key to values.yaml:"
    echo "     signing:"
    echo "       publicKeyData: |"
    sed 's/^/         /' "${KEY_NAME}.pub"
    ;;

sign)
    require_cmd python3 "https://www.python.org"
    MODEL_DIR=""
    PRIVATE_KEY=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --key) PRIVATE_KEY="$2"; shift 2 ;;
            *)     MODEL_DIR="$1"; shift ;;
        esac
    done
    [ -z "$MODEL_DIR" ] && error "Usage: $0 sign <model-dir> [--key <private-key>]"
    [ -d "$MODEL_DIR" ] || error "Directory not found: $MODEL_DIR"

    if ! python3 -c "import model_signing" 2>/dev/null; then
        error "model-signing not installed. Run: pip install model-signing"
    fi

    SIG_PATH="${MODEL_DIR}/model.sig"
    if [ -n "$PRIVATE_KEY" ]; then
        [ -f "$PRIVATE_KEY" ] || error "Private key not found: $PRIVATE_KEY"
        info "Signing model at '$MODEL_DIR' with key '$PRIVATE_KEY'..."
        python3 -m model_signing sign key \
            --private_key "$PRIVATE_KEY" \
            --signature "$SIG_PATH" \
            --ignore-git-paths \
            "$MODEL_DIR"
    else
        info "Signing model at '$MODEL_DIR' with Sigstore keyless (OIDC)..."
        python3 -m model_signing sign sigstore \
            --signature "$SIG_PATH" \
            --ignore-git-paths \
            "$MODEL_DIR"
    fi
    info "Signature written to $SIG_PATH"
    echo ""
    info "Next steps:"
    echo "  1. Verify:  $0 verify $MODEL_DIR ${PRIVATE_KEY:+--key ${PRIVATE_KEY%.pem}.pub}"
    echo "  2. Archive: $0 archive $MODEL_DIR signed-model.tar.gz"
    ;;

verify)
    require_cmd python3 "https://www.python.org"
    MODEL_DIR=""
    PUBLIC_KEY=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --key) PUBLIC_KEY="$2"; shift 2 ;;
            *)     MODEL_DIR="$1"; shift ;;
        esac
    done
    [ -z "$MODEL_DIR" ] && error "Usage: $0 verify <model-dir> [--key <public-key>]"
    [ -d "$MODEL_DIR" ] || error "Directory not found: $MODEL_DIR"

    if ! python3 -c "import model_signing" 2>/dev/null; then
        error "model-signing not installed. Run: pip install model-signing"
    fi

    SIG_PATH="${MODEL_DIR}/model.sig"
    [ -f "$SIG_PATH" ] || error "No signature file at $SIG_PATH. Sign first: $0 sign $MODEL_DIR"

    if [ -n "$PUBLIC_KEY" ]; then
        [ -f "$PUBLIC_KEY" ] || error "Public key not found: $PUBLIC_KEY"
        info "Verifying model at '$MODEL_DIR' with key '$PUBLIC_KEY'..."
        python3 -m model_signing verify key \
            --public_key "$PUBLIC_KEY" \
            --signature "$SIG_PATH" \
            --ignore-git-paths \
            "$MODEL_DIR"
    else
        info "Verifying model at '$MODEL_DIR' with Sigstore keyless..."
        python3 -m model_signing verify sigstore \
            --signature "$SIG_PATH" \
            --ignore-git-paths \
            "$MODEL_DIR"
    fi
    info "Verification passed."
    ;;

archive)
    MODEL_DIR="${1:-}"
    OUTPUT="${2:-}"
    [ -z "$MODEL_DIR" ] && error "Usage: $0 archive <model-dir> <output.tar.gz>"
    [ -z "$OUTPUT" ]    && error "Usage: $0 archive <model-dir> <output.tar.gz>"
    [ -d "$MODEL_DIR" ] || error "Directory not found: $MODEL_DIR"

    SIG_PATH="${MODEL_DIR}/model.sig"
    [ -f "$SIG_PATH" ] || error "No signature at $SIG_PATH. Sign first: $0 sign $MODEL_DIR"

    info "Creating flat archive '$OUTPUT' from '$MODEL_DIR'..."
    tar -czf "$OUTPUT" -C "$MODEL_DIR" .
    info "Archive created: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
    echo ""
    info "To package as OCI image instead:"
    echo "  cat > Containerfile <<EOF"
    echo "  FROM busybox:latest"
    echo "  COPY ${MODEL_DIR}/ /model/"
    echo "  EOF"
    echo "  podman build --platform linux/amd64 -t quay.io/yourorg/signed-model:v1 ."
    echo "  podman push quay.io/yourorg/signed-model:v1"
    ;;

help|--help|-h|"")
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Sign and verify model files using sigstore model-signing."
    echo "The Helm chart integrates with the Model Validation Operator to"
    echo "enforce cryptographic model verification at pod startup."
    echo ""
    echo "Actions:"
    echo "  keygen                            Generate EC P-256 signing key pair"
    echo "  sign     <model-dir> [--key KEY]  Sign model (produces model.sig)"
    echo "  verify   <model-dir> [--key KEY]  Verify model signature"
    echo "  archive  <model-dir> <output>     Create flat tar.gz with model + signature"
    echo "  help                              Show this help"
    echo ""
    echo "Prerequisites:"
    echo "  pip install model-signing"
    echo ""
    echo "Workflow (key-based):"
    echo "  1. Generate keys:         $0 keygen"
    echo "  2. Download your model:   huggingface-cli download Qwen/Qwen2.5-0.5B-Instruct --local-dir ./model-files"
    echo "  3. Sign:                  $0 sign ./model-files --key signing-key.pem"
    echo "  4. Verify:                $0 verify ./model-files --key signing-key.pub"
    echo "  5. Package as OCI image:  podman build + podman push"
    echo "  6. Set signing.enabled=true, signing.modelImage, and signing.publicKeyData in helm/values.yaml"
    echo "  7. Deploy:                helm install hr-assistant helm/ -n hr-assistant"
    echo ""
    echo "The Model Validation Operator will:"
    echo "  a) Detect the validation label on the predictor pod"
    echo "  b) Inject a model-validation init container"
    echo "  c) Verify the signature before the model server starts"
    exit 0
    ;;

*)
    error "Unknown action: $ACTION. Run '$0 help' for usage."
    ;;

esac
