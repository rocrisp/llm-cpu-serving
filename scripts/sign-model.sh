#!/bin/bash
# Sign and verify an OCI model artifact with cosign.
#
# Prerequisites:
#   - cosign v3+   (https://github.com/sigstore/cosign)
#   - oras         (https://oras.land) — only needed for the initial push
#   - Authenticated to your OCI registry (e.g. podman login / docker login)
#
# Usage:
#   ./scripts/sign-model.sh <action> [options]
#
# Actions:
#   generate-keys             Generate a cosign keypair (cosign.key / cosign.pub)
#   push   <model-dir> <ref>  Push model files to an OCI registry
#   sign   <ref>              Sign an OCI artifact (key-based or keyless)
#   verify <ref>              Verify an OCI artifact signature
#   encode-pubkey             Base64-encode cosign.pub for helm/values.yaml
#
# Examples:
#   ./scripts/sign-model.sh generate-keys
#   ./scripts/sign-model.sh push ./model-files quay.io/myorg/qwen25-05b:v1
#   ./scripts/sign-model.sh sign quay.io/myorg/qwen25-05b:v1
#   ./scripts/sign-model.sh verify quay.io/myorg/qwen25-05b:v1
#   ./scripts/sign-model.sh encode-pubkey

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

generate-keys)
    require_cmd cosign "https://github.com/sigstore/cosign#installation"
    info "Generating cosign keypair..."
    cosign generate-key-pair
    info "Created cosign.key (private) and cosign.pub (public)"
    info "Keep cosign.key secret. Distribute cosign.pub for verification."
    echo ""
    info "To add the public key to values.yaml, run:"
    echo "  ./scripts/sign-model.sh encode-pubkey"
    ;;

push)
    require_cmd oras "https://oras.land/docs/installation"
    MODEL_DIR="${1:-}"
    OCI_REF="${2:-}"
    [ -z "$MODEL_DIR" ] && error "Usage: $0 push <model-dir> <oci-ref>"
    [ -z "$OCI_REF" ]   && error "Usage: $0 push <model-dir> <oci-ref>"
    [ -d "$MODEL_DIR" ] || error "Directory not found: $MODEL_DIR"

    info "Pushing model files from '$MODEL_DIR' to '$OCI_REF'..."
    oras push "$OCI_REF" "$MODEL_DIR/:application/vnd.oci.image.layer.v1.tar+gzip"
    info "Model pushed to $OCI_REF"
    echo ""
    info "Next step — sign the artifact:"
    echo "  ./scripts/sign-model.sh sign $OCI_REF"
    ;;

sign)
    require_cmd cosign "https://github.com/sigstore/cosign#installation"
    OCI_REF="${1:-}"
    [ -z "$OCI_REF" ] && error "Usage: $0 sign <oci-ref>"

    if [ -f cosign.key ]; then
        info "Signing '$OCI_REF' with cosign.key (key-based)..."
        cosign sign --key cosign.key "$OCI_REF"
    else
        info "No cosign.key found — using keyless signing (OIDC)..."
        info "Your browser will open for authentication."
        cosign sign "$OCI_REF"
    fi
    info "Artifact signed successfully."
    ;;

verify)
    require_cmd cosign "https://github.com/sigstore/cosign#installation"
    OCI_REF="${1:-}"
    [ -z "$OCI_REF" ] && error "Usage: $0 verify <oci-ref>"

    if [ -f cosign.pub ]; then
        info "Verifying '$OCI_REF' with cosign.pub (key-based)..."
        cosign verify --key cosign.pub "$OCI_REF"
    else
        CERT_ID="${COSIGN_CERTIFICATE_IDENTITY:-}"
        CERT_ISSUER="${COSIGN_CERTIFICATE_OIDC_ISSUER:-}"
        if [ -n "$CERT_ID" ] && [ -n "$CERT_ISSUER" ]; then
            info "Verifying '$OCI_REF' with keyless identity..."
            cosign verify \
                --certificate-identity="$CERT_ID" \
                --certificate-oidc-issuer="$CERT_ISSUER" \
                "$OCI_REF"
        else
            error "No cosign.pub found and COSIGN_CERTIFICATE_IDENTITY / COSIGN_CERTIFICATE_OIDC_ISSUER not set."
        fi
    fi
    info "Verification passed."
    ;;

encode-pubkey)
    [ -f cosign.pub ] || error "cosign.pub not found. Run: $0 generate-keys"
    ENCODED=$(base64 < cosign.pub | tr -d '\n')
    info "Base64-encoded public key:"
    echo ""
    echo "  $ENCODED"
    echo ""
    info "Paste this into helm/values.yaml under signing.publicKey"
    ;;

*)
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Actions:"
    echo "  generate-keys             Generate cosign keypair"
    echo "  push   <model-dir> <ref>  Push model to OCI registry"
    echo "  sign   <ref>              Sign an OCI artifact"
    echo "  verify <ref>              Verify an OCI artifact"
    echo "  encode-pubkey             Base64-encode cosign.pub for values.yaml"
    exit 1
    ;;

esac
