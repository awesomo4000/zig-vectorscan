# API Reference

## Vectorscan

High-performance multi-pattern regex matching. Use when you need fast scanning and only need end-of-match positions.

```zig
const vectorscan = @import("vectorscan");
```

### Types

| Type | Description |
|------|-------------|
| `Database` | Compiled pattern database |
| `Scratch` | Per-thread scratch space for scanning |
| `Match` | Match result with `.id`, `.from`, `.to` |

### Functions

#### `compile`
```zig
fn compile(pattern: []const u8, flags: c_uint, mode: c_uint, allocator: Allocator) !*Database
```
Compile a single pattern. Use `freeDatabase` when done.

#### `compileMulti`
```zig
fn compileMulti(patterns: []const []const u8, flags: []const c_uint, ids: []const c_uint, mode: c_uint, allocator: Allocator) !*Database
```
Compile multiple patterns into one database. Each pattern gets an ID for identifying matches.

**Note:** Patterns must be null-terminated. Use `allocator.dupeZ()` for runtime strings.

#### `allocScratch`
```zig
fn allocScratch(database: *Database) !*Scratch
```
Allocate scratch space. One per thread. Use `freeScratch` when done.

#### `scan`
```zig
fn scan(database: *Database, data: []const u8, scratch: *Scratch, allocator: Allocator) ![]Match
```
Scan data for matches. Returns owned slice - caller must `allocator.free()`.

#### `freeDatabase` / `freeScratch`
```zig
fn freeDatabase(database: *Database) void
fn freeScratch(scratch: *Scratch) void
```

#### `version`
```zig
fn version() []const u8  // Returns "5.4.12"
```

### Flags

| Flag | Description |
|------|-------------|
| `FLAG_CASELESS` | Case-insensitive matching |
| `FLAG_DOTALL` | `.` matches newlines |
| `FLAG_MULTILINE` | `^`/`$` match line boundaries |
| `FLAG_SINGLEMATCH` | Report only first match |
| `FLAG_UTF8` | UTF-8 mode |
| `FLAG_UCP` | Unicode character properties |

### Modes

| Mode | Description |
|------|-------------|
| `MODE_BLOCK` | Non-streaming, single block |
| `MODE_STREAM` | Streaming across chunks |
| `MODE_VECTORED` | Multiple non-contiguous blocks |

### Example

```zig
const allocator = std.heap.page_allocator;

// Single pattern
const db = try vectorscan.compile("test", vectorscan.FLAG_CASELESS, vectorscan.MODE_BLOCK, allocator);
defer vectorscan.freeDatabase(db);

const scratch = try vectorscan.allocScratch(db);
defer vectorscan.freeScratch(scratch);

const matches = try vectorscan.scan(db, "This is a TEST", scratch, allocator);
defer allocator.free(matches);

for (matches) |m| {
    std.debug.print("Match id={} at {}-{}\n", .{ m.id, m.from, m.to });
}
```

---

## Chimera

Hybrid Hyperscan + PCRE engine. Use when you need accurate start-of-match positions or full PCRE compatibility.

```zig
const chimera = @import("chimera");
```

### Types

| Type | Description |
|------|-------------|
| `Database` | Compiled pattern database |
| `Scratch` | Per-thread scratch space |
| `Match` | Match result with `.id`, `.from`, `.to` |

### Functions

#### `compileMulti`
```zig
fn compileMulti(patterns: []const [:0]const u8, flags: []const c_uint, ids: []const c_uint, allocator: Allocator) !*Database
```
Compile PCRE patterns. Patterns must be null-terminated (`[:0]const u8`).

#### `allocScratch`
```zig
fn allocScratch(database: *Database) !*Scratch
```

#### `scan`
```zig
fn scan(database: *Database, data: []const u8, scratch: *Scratch, allocator: Allocator) ![]Match
```
Returns matches with accurate `.from` positions (unlike Vectorscan which only guarantees `.to`).

#### `freeDatabase` / `freeScratch`
```zig
fn freeDatabase(database: *Database) void
fn freeScratch(scratch: *Scratch) void
```

### Example

```zig
const allocator = std.heap.page_allocator;

// URL detection with accurate positions
const patterns = [_][:0]const u8{"https?://[^\\s]+"};
const flags = [_]c_uint{0};
const ids = [_]c_uint{0};

const db = try chimera.compileMulti(&patterns, &flags, &ids, allocator);
defer chimera.freeDatabase(db);

const scratch = try chimera.allocScratch(db);
defer chimera.freeScratch(scratch);

const text = "Visit https://example.com for info";
const matches = try chimera.scan(db, text, scratch, allocator);
defer allocator.free(matches);

for (matches) |m| {
    std.debug.print("Found: {s}\n", .{text[m.from..m.to]});
}
```

---

## When to Use Which

| Use Case | Library |
|----------|---------|
| High-throughput scanning | Vectorscan |
| Need start-of-match position | Chimera |
| Full PCRE syntax | Chimera |
| Streaming data | Vectorscan |
| Memory-constrained | Vectorscan |
