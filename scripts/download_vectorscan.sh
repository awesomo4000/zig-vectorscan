#!/usr/bin/env bash
# Download and extract Vectorscan source to vendor/vectorscan/

set -euo pipefail

VECTORSCAN_VERSION="5.4.12"
VECTORSCAN_URL="https://github.com/VectorCamp/vectorscan/archive/refs/tags/vectorscan/${VECTORSCAN_VERSION}.tar.gz"
VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor"
TARGET_DIR="${VENDOR_DIR}/vectorscan"

echo "Downloading Vectorscan ${VECTORSCAN_VERSION}..."
mkdir -p "${VENDOR_DIR}"

# Download to temporary location
TEMP_FILE=$(mktemp)
trap "rm -f ${TEMP_FILE}" EXIT

curl -L -o "${TEMP_FILE}" "${VECTORSCAN_URL}"

echo "Extracting to ${TARGET_DIR}..."
rm -rf "${TARGET_DIR}"

# Extract and rename (tar creates vectorscan-vectorscan-5.4.12/)
tar -xzf "${TEMP_FILE}" -C "${VENDOR_DIR}"
mv "${VENDOR_DIR}/vectorscan-vectorscan-${VECTORSCAN_VERSION}" "${TARGET_DIR}"

echo "✓ Vectorscan ${VECTORSCAN_VERSION} downloaded to ${TARGET_DIR}"
echo ""
echo "Next steps:"
echo "  1. Run scripts/download_pcre.sh to download PCRE dependency"
echo "  2. Run scripts/apply_patches.sh to apply compatibility patches"
echo "  3. Run 'zig build install-vectorscan' to build libraries"
