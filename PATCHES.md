# Patches Applied to Vectorscan 5.4.12

This file documents modifications made to the vendored vectorscan source to enable building with modern toolchains.

## 1. PCRE CMake Modernization

**File**: `pcre/CMakeLists.txt`

### Line 79: Update minimum CMake version
```diff
- CMAKE_MINIMUM_REQUIRED(VERSION 2.8.5)
+ CMAKE_MINIMUM_REQUIRED(VERSION 3.10)
```
**Reason**: CMake 4.x no longer supports 2.8.x minimum version syntax. Version 3.10 avoids deprecation warnings.

### Line 80: Remove deprecated policy
```diff
- CMAKE_POLICY(SET CMP0026 OLD)
+ # Removed deprecated CMP0026 policy (not allowed in modern CMake)
```
**Reason**: CMP0026 (LOCATION property) cannot be set to OLD in CMake 3.0+.

### Line 839: Use generator expression for target location
```diff
- GET_TARGET_PROPERTY(PCREGREP_EXE pcregrep DEBUG_LOCATION)
+ SET(PCREGREP_EXE $<TARGET_FILE:pcregrep>)
```
**Reason**: LOCATION property is deprecated; generator expressions are the modern approach.

### Line 842: Use generator expression for target location
```diff
- GET_TARGET_PROPERTY(PCRETEST_EXE pcretest DEBUG_LOCATION)
+ SET(PCRETEST_EXE $<TARGET_FILE:pcretest>)
```
**Reason**: Same as above.

## 2. Chimera C++17 Compatibility

**File**: `chimera/ch_compile.cpp`

### Line 499: Qualify std::move call
```diff
- pcres.push_back(move(patternData));
+ pcres.push_back(std::move(patternData));
```
**Reason**: Unqualified `move()` call triggers `-Werror,-Wunqualified-std-cast-call` in modern Clang with C++17+.

## 3. ARM Architecture Flags for zig cc Compatibility

**Files**: `CMakeLists.txt`, `cmake/archdetect.cmake`

### CMakeLists.txt: Use -mcpu for ARM architectures
```diff
- if (ARCH_PPC64EL)
+ if (ARCH_PPC64EL OR ARCH_ARM32 OR ARCH_AARCH64)
```
**Reason**: ARM architectures (like Apple Silicon) require `-mcpu` flag instead of `-march`. This ensures ARM builds use the correct compiler flags, matching PowerPC behavior.

### archdetect.cmake: Use native CPU detection
```diff
- set(GNUCC_ARCH ${ARMV8_ARCH})
+ set(GNUCC_ARCH native)
```
**Reason**: Using `native` CPU detection instead of hardcoded `armv8-a` allows the compiler to optimize for the actual CPU (e.g., Apple M4 with crypto extensions). Works with zig cc's CPU detection.

---

## Version Information

- **Vectorscan Version**: 5.4.12
- **PCRE Version**: 8.45 (vendored in `pcre/`)
- **Patches Applied**: 01/10/2025
- **Build System**: Zig build system wrapping CMake

## Upstream Status

These patches are local modifications for build compatibility. Consider submitting upstream if vectorscan project is still accepting PRs.
