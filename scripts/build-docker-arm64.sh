#! /usr/bin/env bash
# Build the ErsatzTV Docker image for linux/arm64.
#
# Local usage:
#   ./scripts/build-docker-arm64.sh
#   ./scripts/build-docker-arm64.sh --tag myregistry/ersatztv:test
#
# Note: building for arm64 on an x86 host requires QEMU binfmt support:
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# CI (push-by-digest) usage:
#   ./scripts/build-docker-arm64.sh \
#     --info-version "26.5.1-docker-arm64" \
#     --push-by-digest \
#     --image-name ersatztv/legacy \
#     --image-name ghcr.io/ersatztv/legacy \
#     --metadata-file metadata.json
#
# The ersatztv-channel binary must exist at the repo root before building.
# Download it from: https://github.com/ErsatzTV/next/releases/tag/develop
#   TARGET=linux-arm64
#   gh release download develop --repo ErsatzTV/next --pattern "ersatztv-next-*-${TARGET}.tar.gz"
#   tar xzvf ersatztv-next-*-${TARGET}.tar.gz --strip-components 1
#   mv ersatztv-next-*/ersatztv-channel .

set -euo pipefail

ARCH="arm64"
PLATFORM="linux/arm64"
DOCKERFILE="docker/arm64/Dockerfile"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

INFO_VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")-local"
TAGS=()
PUSH_BY_DIGEST=false
IMAGE_NAMES=()
METADATA_FILE=""
BUILD_CONFIG="release"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the ErsatzTV Docker image for ${PLATFORM}.

Options:
  --info-version VERSION   Informational version string (default: from git tag)
  --tag TAG                Local image tag; repeatable (default: ersatztv-local:${ARCH})
  --push-by-digest         Push to registry without a tag (for CI multi-arch manifest builds)
  --image-name NAME        Registry image name for push-by-digest mode; repeatable
  --metadata-file FILE     Write buildx metadata JSON here (used to extract the digest in CI)
  --build-config CONFIG    release or debug (default: release)
  --help                   Show this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --info-version)   INFO_VERSION="$2";        shift 2 ;;
        --tag)            TAGS+=("$2");              shift 2 ;;
        --push-by-digest) PUSH_BY_DIGEST=true;       shift   ;;
        --image-name)     IMAGE_NAMES+=("$2");       shift 2 ;;
        --metadata-file)  METADATA_FILE="$2";        shift 2 ;;
        --build-config)   BUILD_CONFIG="$2";         shift 2 ;;
        --help)           usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ${#TAGS[@]} -eq 0 ]]; then
    TAGS=("ersatztv-local:${ARCH}")
fi

if [[ ! -f "${REPO_ROOT}/ersatztv-channel" ]]; then
    echo "Warning: ersatztv-channel not found at repo root — the Dockerfile will fail." >&2
    echo "         See the script header for download instructions." >&2
fi

CMD=(docker buildx build)
CMD+=(--file "${DOCKERFILE}")
CMD+=(--platform "${PLATFORM}")
CMD+=(--build-arg "INFO_VERSION=${INFO_VERSION}")
CMD+=(--build-arg "BUILD_CONFIG=${BUILD_CONFIG}")

if [[ "${PUSH_BY_DIGEST}" == true ]]; then
    if [[ ${#IMAGE_NAMES[@]} -eq 0 ]]; then
        echo "Error: --push-by-digest requires at least one --image-name" >&2
        exit 1
    fi
    CMD+=(--provenance=false)
    for name in "${IMAGE_NAMES[@]}"; do
        CMD+=(--output "type=image,name=${name},name-canonical=true,push-by-digest=true")
    done
    [[ -n "${METADATA_FILE}" ]] && CMD+=(--metadata-file "${METADATA_FILE}")
    CMD+=(--push)
else
    for tag in "${TAGS[@]}"; do
        CMD+=(--tag "${tag}")
    done
    CMD+=(--load)
fi

CMD+=(.)

echo "==> Building ${ARCH} image"
echo "    platform:     ${PLATFORM}"
echo "    dockerfile:   ${DOCKERFILE}"
echo "    info_version: ${INFO_VERSION}"
echo "    build_config: ${BUILD_CONFIG}"
if [[ "${PUSH_BY_DIGEST}" == true ]]; then
    printf '    destination:  %s\n' "${IMAGE_NAMES[@]}"
else
    printf '    tag:          %s\n' "${TAGS[@]}"
fi
echo ""

exec "${CMD[@]}"
