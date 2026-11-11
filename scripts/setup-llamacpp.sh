#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor"
LLAMA_TAG="${LLAMA_TAG:-b12289}"
ZIP_NAME="llama-${LLAMA_TAG}-xcframework.zip"
DOWNLOAD_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/${ZIP_NAME}"
TARGET_XCFRAMEWORK="${VENDOR_DIR}/llama.xcframework"

if [[ -d "${TARGET_XCFRAMEWORK}" && "${1:-}" != "--force" ]]; then
  echo "llama.xcframework already present at ${TARGET_XCFRAMEWORK}"
  exit 0
fi

mkdir -p "${VENDOR_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading ${ZIP_NAME} (${LLAMA_TAG})..."
curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ZIP_NAME}"

echo "Extracting xcframework..."
unzip -q "${TMP_DIR}/${ZIP_NAME}" -d "${TMP_DIR}/extracted"

FOUND_XCFRAMEWORK="$(find "${TMP_DIR}/extracted" -maxdepth 3 -name "llama.xcframework" -type d | head -n 1)"
if [[ -z "${FOUND_XCFRAMEWORK}" ]]; then
  echo "Error: llama.xcframework not found inside ${ZIP_NAME}" >&2
  exit 1
fi

rm -rf "${TARGET_XCFRAMEWORK}"
mv "${FOUND_XCFRAMEWORK}" "${TARGET_XCFRAMEWORK}"

echo "Installed ${TARGET_XCFRAMEWORK}"
