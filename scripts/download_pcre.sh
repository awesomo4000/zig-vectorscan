#!/usr/bin/env bash
# Download and extract PCRE source to vendor/vectorscan/pcre/

set -euo pipefail

PCRE_VERSION="8.45"
PCRE_URL="https://sourceforge.net/projects/pcre/files/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz/download"
VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor"
TARGET_DIR="${VENDOR_DIR}/vectorscan/pcre"

if [ ! -d "${VENDOR_DIR}/vectorscan" ]; then
    echo "Error: Vectorscan source not found at ${VENDOR_DIR}/vectorscan"
    echo "Run scripts/download_vectorscan.sh first"
    exit 1
fi

echo "Downloading PCRE ${PCRE_VERSION}..."
mkdir -p "${VENDOR_DIR}"

# Download to temporary location
TEMP_FILE=$(mktemp)
trap "rm -f ${TEMP_FILE}" EXIT

curl -L -o "${TEMP_FILE}" "${PCRE_URL}"

echo "Extracting to ${TARGET_DIR}..."
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"

# Extract and move contents up one level (tar creates pcre-8.45/)
tar -xzf "${TEMP_FILE}" -C "${VENDOR_DIR}"
mv "${VENDOR_DIR}/pcre-${PCRE_VERSION}"/* "${TARGET_DIR}/"
rmdir "${VENDOR_DIR}/pcre-${PCRE_VERSION}"

echo "✓ PCRE ${PCRE_VERSION} downloaded to ${TARGET_DIR}"
echo ""
echo "Next steps:"
echo "  1. Run scripts/apply_patches.sh to apply compatibility patches"
echo "  2. Run 'zig build install-vectorscan' to build libraries"
