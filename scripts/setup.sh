#!/usr/bin/env bash
# All-in-one setup script for zig-vectorscan
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up zig-vectorscan..."
echo ""

"${SCRIPT_DIR}/download_vectorscan.sh"
"${SCRIPT_DIR}/download_pcre.sh"
"${SCRIPT_DIR}/apply_patches.sh"

echo ""
echo "Setup complete! Run 'zig build' to compile."
