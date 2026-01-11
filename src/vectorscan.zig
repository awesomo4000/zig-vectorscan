const std = @import("std");

/// Vectorscan/Hyperscan Zig bindings
/// High-performance multi-pattern regex matching library

// ============================================================================
// C API Bindings
// ============================================================================

pub const c = @cImport({
    @cInclude("hs/hs.h");
});

// Re-export common types with Zig naming
pub const Database = c.hs_database_t;
pub const Scratch = c.hs_scratch_t;
pub const CompileError = c.hs_compile_error_t;
pub const Error = c.hs_error_t;

// Error codes
pub const SUCCESS = c.HS_SUCCESS;
pub const INVALID = c.HS_INVALID;
pub const NOMEM = c.HS_NOMEM;
pub const SCAN_TERMINATED = c.HS_SCAN_TERMINATED;
pub const COMPILER_ERROR = c.HS_COMPILER_ERROR;
pub const DB_VERSION_ERROR = c.HS_DB_VERSION_ERROR;
pub const DB_PLATFORM_ERROR = c.HS_DB_PLATFORM_ERROR;
pub const DB_MODE_ERROR = c.HS_DB_MODE_ERROR;
pub const BAD_ALIGN = c.HS_BAD_ALIGN;
pub const BAD_ALLOC = c.HS_BAD_ALLOC;
pub const SCRATCH_IN_USE = c.HS_SCRATCH_IN_USE;
pub const ARCH_ERROR = c.HS_ARCH_ERROR;
pub const INSUFFICIENT_SPACE = c.HS_INSUFFICIENT_SPACE;
pub const UNKNOWN_ERROR = c.HS_UNKNOWN_ERROR;

// Compile flags
pub const FLAG_CASELESS = c.HS_FLAG_CASELESS;
pub const FLAG_DOTALL = c.HS_FLAG_DOTALL;
pub const FLAG_MULTILINE = c.HS_FLAG_MULTILINE;
pub const FLAG_SINGLEMATCH = c.HS_FLAG_SINGLEMATCH;
pub const FLAG_ALLOWEMPTY = c.HS_FLAG_ALLOWEMPTY;
pub const FLAG_UTF8 = c.HS_FLAG_UTF8;
pub const FLAG_UCP = c.HS_FLAG_UCP;
pub const FLAG_PREFILTER = c.HS_FLAG_PREFILTER;
pub const FLAG_SOM_LEFTMOST = c.HS_FLAG_SOM_LEFTMOST;

// Scan modes
pub const MODE_BLOCK = c.HS_MODE_BLOCK;
pub const MODE_STREAM = c.HS_MODE_STREAM;
pub const MODE_VECTORED = c.HS_MODE_VECTORED;

// ============================================================================
// High-level Zig API
// ============================================================================

/// Compile a single regex pattern into a database
pub fn compile(
    pattern: []const u8,
    flags: c_uint,
    mode: c_uint,
    allocator: std.mem.Allocator,
) !*Database {
    _ = allocator; // For future use

    var database: ?*Database = null;
    var compile_err: ?*CompileError = null;

    const result = c.hs_compile(
        pattern.ptr,
        flags,
        mode,
        null, // platform info (null = current platform)
        &database,
        &compile_err,
    );

    if (result != SUCCESS) {
        if (compile_err) |err| {
            defer _ = c.hs_free_compile_error(err);
            return error.CompileError; // TODO: extract error message
        }
        return error.UnknownCompileError;
    }

    return database.?;
}

/// Compile multiple patterns into a single database
///
/// IMPORTANT: Vectorscan requires null-terminated C strings. When loading patterns
/// from external sources (files, etc.), use allocator.dupeZ() instead of allocator.dupe()
/// to create null-terminated copies. Compile-time string literals in Zig are automatically
/// null-terminated, so they work correctly without modification.
///
/// Example of correct usage with file-loaded patterns:
///   const pattern = try allocator.dupeZ(u8, trimmed_line);  // ✅ Null-terminated
///   defer allocator.free(pattern);
///
/// Example of incorrect usage (will cause unpredictable matching failures):
///   const pattern = try allocator.dupe(u8, trimmed_line);   // ❌ NOT null-terminated
pub fn compileMulti(
    patterns: []const []const u8,
    flags: []const c_uint,
    ids: []const c_uint,
    mode: c_uint,
    allocator: std.mem.Allocator,
) !*Database {
    if (patterns.len != flags.len or patterns.len != ids.len) {
        return error.LengthMismatch;
    }

    // Convert Zig slices to C arrays
    const pattern_ptrs = try allocator.alloc([*c]const u8, patterns.len);
    defer allocator.free(pattern_ptrs);

    for (patterns, 0..) |pattern, i| {
        pattern_ptrs[i] = pattern.ptr;
    }

    var database: ?*Database = null;
    var compile_err: ?*CompileError = null;

    const result = c.hs_compile_multi(
        pattern_ptrs.ptr,
        flags.ptr,
        ids.ptr,
        @intCast(patterns.len),
        mode,
        null, // platform info
        &database,
        &compile_err,
    );

    if (result != SUCCESS) {
        if (compile_err) |err| {
            defer _ = c.hs_free_compile_error(err);
            return error.CompileError;
        }
        return error.UnknownCompileError;
    }

    return database.?;
}

/// Allocate scratch space for a database
pub fn allocScratch(database: *Database) !*Scratch {
    var scratch: ?*Scratch = null;

    const result = c.hs_alloc_scratch(database, &scratch);

    if (result != SUCCESS) {
        return error.ScratchAllocFailed;
    }

    return scratch.?;
}

/// Match callback context
pub const MatchContext = struct {
    matches: std.ArrayList(Match),
    allocator: std.mem.Allocator,
};

/// A single match result
pub const Match = struct {
    id: u32,
    from: u64,
    to: u64,
};

/// Callback function for matches (called from C)
export fn matchCallback(
    id: c_uint,
    from: c_ulonglong,
    to: c_ulonglong,
    flags: c_uint,
    context: ?*anyopaque,
) callconv(.c) c_int {
    _ = flags;

    const ctx: *MatchContext = @ptrCast(@alignCast(context.?));

    ctx.matches.append(ctx.allocator, Match{
        .id = id,
        .from = from,
        .to = to,
    }) catch return 1; // Return non-zero to stop scanning on error

    return 0; // 0 = continue scanning
}

/// Scan data for matches
pub fn scan(
    database: *Database,
    data: []const u8,
    scratch: *Scratch,
    allocator: std.mem.Allocator,
) ![]Match {
    var ctx = MatchContext{
        .matches = std.ArrayList(Match){},
        .allocator = allocator,
    };
    defer ctx.matches.deinit(allocator);

    const result = c.hs_scan(
        database,
        data.ptr,
        @intCast(data.len),
        0, // flags
        scratch,
        matchCallback,
        &ctx,
    );

    if (result != SUCCESS and result != SCAN_TERMINATED) {
        return error.ScanFailed;
    }

    return try ctx.matches.toOwnedSlice(allocator);
}

/// Free a compiled database
pub fn freeDatabase(database: *Database) void {
    _ = c.hs_free_database(database);
}

/// Free scratch space
pub fn freeScratch(scratch: *Scratch) void {
    _ = c.hs_free_scratch(scratch);
}

/// Get vectorscan version string
pub fn version() []const u8 {
    const ver = c.hs_version();
    return std.mem.span(ver);
}

// ============================================================================
// Tests
// ============================================================================

test "vectorscan basic compile and scan" {
    const allocator = std.testing.allocator;

    // Compile a simple pattern
    const pattern = "test";
    const db = try compile(pattern, FLAG_CASELESS, MODE_BLOCK, allocator);
    defer freeDatabase(db);

    // Allocate scratch space
    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    // Scan some data
    const data = "This is a test string with TEST in it";
    const matches = try scan(db, data, scratch, allocator);
    defer allocator.free(matches);

    // Should find 2 matches (case-insensitive)
    try std.testing.expectEqual(@as(usize, 2), matches.len);

    // First match: "test" at position 10-14
    try std.testing.expectEqual(@as(u64, 14), matches[0].to);

    // Second match: "TEST" at position 27-31
    try std.testing.expectEqual(@as(u64, 31), matches[1].to);
}

test "vectorscan multi-pattern" {
    const allocator = std.testing.allocator;

    const patterns = [_][]const u8{ "foo", "bar", "baz" };
    const flags_arr = [_]c_uint{ 0, 0, 0 };
    const ids = [_]c_uint{ 1, 2, 3 };

    const db = try compileMulti(&patterns, &flags_arr, &ids, MODE_BLOCK, allocator);
    defer freeDatabase(db);

    const scratch = try allocScratch(db);
    defer freeScratch(scratch);

    const data = "foo and bar and baz";
    const matches = try scan(db, data, scratch, allocator);
    defer allocator.free(matches);

    // Should find 3 matches
    try std.testing.expectEqual(@as(usize, 3), matches.len);

    // Check IDs match
    try std.testing.expectEqual(@as(u32, 1), matches[0].id); // foo
    try std.testing.expectEqual(@as(u32, 2), matches[1].id); // bar
    try std.testing.expectEqual(@as(u32, 3), matches[2].id); // baz
}

test "vectorscan version" {
    const ver = version();
    try std.testing.expect(ver.len > 0);
    std.debug.print("\nVectorscan version: {s}\n", .{ver});
}
