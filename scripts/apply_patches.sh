#!/usr/bin/env bash
# Apply compatibility patches to vendored Vectorscan + PCRE source
# See vendor/VECTORSCAN-PATCHES.md for details

set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/vectorscan"
PCRE_CMAKE="${VENDOR_DIR}/pcre/CMakeLists.txt"
CHIMERA_COMPILE="${VENDOR_DIR}/chimera/ch_compile.cpp"
VECTORSCAN_CMAKE="${VENDOR_DIR}/CMakeLists.txt"
ARCHDETECT_CMAKE="${VENDOR_DIR}/cmake/archdetect.cmake"

if [ ! -d "${VENDOR_DIR}" ]; then
    echo "Error: Vectorscan source not found at ${VENDOR_DIR}"
    echo "Run scripts/download_vectorscan.sh first"
    exit 1
fi

if [ ! -d "${VENDOR_DIR}/pcre" ]; then
    echo "Error: PCRE source not found at ${VENDOR_DIR}/pcre"
    echo "Run scripts/download_pcre.sh first"
    exit 1
fi

echo "Applying patches to Vectorscan 5.4.12 + PCRE 8.45..."
echo ""

# Patch 1: PCRE CMake modernization
echo "1. Updating PCRE CMakeLists.txt for modern CMake..."

# Update minimum CMake version (3.10 to avoid deprecation warnings)
sed -i '' 's/CMAKE_MINIMUM_REQUIRED(VERSION 2.8.5)/CMAKE_MINIMUM_REQUIRED(VERSION 3.10)/' "${PCRE_CMAKE}"

# Remove deprecated CMP0026 policy line
sed -i '' '/CMAKE_POLICY(SET CMP0026 OLD)/d' "${PCRE_CMAKE}"

# Replace GET_TARGET_PROPERTY with generator expressions
sed -i '' 's/GET_TARGET_PROPERTY(PCREGREP_EXE pcregrep DEBUG_LOCATION)/SET(PCREGREP_EXE $<TARGET_FILE:pcregrep>)/' "${PCRE_CMAKE}"
sed -i '' 's/GET_TARGET_PROPERTY(PCRETEST_EXE pcretest DEBUG_LOCATION)/SET(PCRETEST_EXE $<TARGET_FILE:pcretest>)/' "${PCRE_CMAKE}"

echo "   ✓ PCRE CMakeLists.txt updated"

# Patch 2: Chimera C++17 compatibility
echo "2. Fixing Chimera C++17 compatibility..."

# Qualify std::move call
sed -i '' 's/pcres\.push_back(move(patternData));/pcres.push_back(std::move(patternData));/' "${CHIMERA_COMPILE}"

echo "   ✓ Chimera ch_compile.cpp updated"

# Patch 3: ARM architecture flag fix for zig cc compatibility
echo "3. Fixing ARM architecture flags for zig cc..."

# Use -mcpu instead of -march for ARM (not just PowerPC)
sed -i '' 's/if (ARCH_PPC64EL)/if (ARCH_PPC64EL OR ARCH_ARM32 OR ARCH_AARCH64)/' "${VECTORSCAN_CMAKE}"

# Use native CPU detection instead of hardcoded armv8-a
sed -i '' 's/set(GNUCC_ARCH ${ARMV8_ARCH})/set(GNUCC_ARCH native)/' "${ARCHDETECT_CMAKE}"

echo "   ✓ CMakeLists.txt and archdetect.cmake updated"
echo ""
echo "✓ All patches applied successfully!"
echo ""
echo "See ${VENDOR_DIR}/PATCHES.md for full patch documentation."
echo ""
echo "Next step:"
echo "  Run 'zig build install-vectorscan' to build libraries"
