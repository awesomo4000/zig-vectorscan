# zig-vectorscan

Zig bindings for [Vectorscan](https://github.com/VectorCamp/vectorscan), a portable fork of Intel's Hyperscan high-performance regex library. Includes Chimera for PCRE-compatible matching with accurate match positions.

## Build Dependencies

| Dependency | macOS | Linux |
|------------|-------|-------|
| Ragel | `brew install ragel` | `apt install ragel` |
| Boost | `brew install boost` | `apt install libboost-dev` |
| CMake 3.10+ | `brew install cmake` | `apt install cmake` |

## Quick Start

```bash
./scripts/setup.sh   # Download & patch Vectorscan
zig build             # Build libraries
zig build test        # Run tests
```

## Using as a Dependency

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_vectorscan = .{
        .path = "../zig-vectorscan",  // or use .url for remote
    },
},
```

In your `build.zig`:

```zig
const vectorscan_dep = b.dependency("zig_vectorscan", .{
    .target = target,
    .optimize = optimize,
});

// Add the module
exe.root_module.addImport("vectorscan", vectorscan_dep.module("vectorscan"));
exe.root_module.addImport("chimera", vectorscan_dep.module("chimera"));

// Link the libraries (required)
exe.linkLibCpp();
exe.addObjectFile(vectorscan_dep.path("zig-out/lib/libhs-5.4.12.a"));
exe.addObjectFile(vectorscan_dep.path("zig-out/lib/libchimera-5.4.12.a"));
exe.addObjectFile(vectorscan_dep.path("zig-out/lib/libpcre-5.4.12.a"));
```

## Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `-Dmcpu=<target>` | `native` | CPU optimization target |
| `-Dforce-vectorscan` | `false` | Force CMake rebuild |
| `-Doptimize=<mode>` | `Debug` | Optimization level |

## Documentation

- [API Reference](API.md) - Zig API documentation
- [PATCHES.md](PATCHES.md) - Build patches applied to Vectorscan

## Versions

- Vectorscan: 5.4.12
- PCRE: 8.45
- Zig: 0.15.2+

## License

Vectorscan is BSD-3-Clause.
